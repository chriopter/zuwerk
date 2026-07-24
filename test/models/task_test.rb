require "test_helper"

class TaskTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Launch")
    @human = User.create!(name: "Ada", email: "ada@example.com", password: "password1")
  end

  test "task belongs to one project and stores a rich description" do
    task = Task.create!(project: @project, creator: @human, title: "Prepare launch", description: "**Ready** for review")

    assert_equal @project, task.project
    assert_equal @human, task.creator
    assert task.open?
    assert_includes task.description.to_plain_text, "Ready"
  end

  test "task title is required and status can be completed" do
    task = Task.new(project: @project, creator: @human)

    assert_not task.valid?
    task.update(title: "Prepare launch", status: :completed)
    assert task.completed?
  end

  test "comments belong to the task and store rich text" do
    task = Task.create!(project: @project, creator: @human, title: "Prepare launch")
    comment = task.comments.create!(author: @human, body: "Looks <strong>good</strong>")

    assert_equal @human, comment.author
    assert_includes comment.body.to_plain_text, "Looks good"
  end

  test "empty comments are rejected" do
    task = Task.create!(project: @project, creator: @human, title: "Prepare launch")

    assert_not task.comments.new(author: @human, body: "").valid?
  end

  test "tasks form an ordered ancestry tree inside their project" do
    parent = Task.create!(project: @project, creator: @human, title: "Launch", position: 1)
    later = Task.create!(project: @project, creator: @human, title: "Later", parent: parent, position: 2)
    earlier = Task.create!(project: @project, creator: @human, title: "Earlier", parent: parent, position: 1)

    assert_equal parent, earlier.parent
    assert_equal [ earlier, later ], parent.children.ordered
    assert_equal 1, earlier.depth
  end

  test "moving between parents compacts both sibling lists and inserts at the requested position" do
    parent = Task.create!(project: @project, creator: @human, title: "Parent", position: 0)
    first = Task.create!(project: @project, creator: @human, title: "First", parent: parent, position: 0)
    second = Task.create!(project: @project, creator: @human, title: "Second", parent: parent, position: 1)
    moved = Task.create!(project: @project, creator: @human, title: "Moved", position: 1)

    moved.move_to!(parent: parent, position: 1)

    assert_equal [ [ first.id, 0 ], [ moved.id, 1 ], [ second.id, 2 ] ], parent.children.ordered.pluck(:id, :position)
    assert_equal [ [ parent.id, 0 ] ], @project.tasks.roots.ordered.pluck(:id, :position)
  end

  test "an invalid move rolls back hierarchy and positions" do
    parent = Task.create!(project: @project, creator: @human, title: "Parent", position: 0)
    child = Task.create!(project: @project, creator: @human, title: "Child", parent: parent, position: 0)
    sibling = Task.create!(project: @project, creator: @human, title: "Sibling", position: 1)

    assert_raises(ActiveRecord::RecordInvalid) { parent.move_to!(parent: child, position: 0) }

    assert_nil parent.reload.parent
    assert_equal [ [ parent.id, 0 ], [ sibling.id, 1 ] ], @project.tasks.roots.ordered.pluck(:id, :position)
    assert_equal [ [ child.id, 0 ] ], parent.children.ordered.pluck(:id, :position)
  end

  test "a move to a parent in another project is rejected without changing either project" do
    other_project = Project.create!(name: "Other")
    foreign_parent = Task.create!(project: other_project, creator: @human, title: "Foreign", position: 7)
    moved = Task.create!(project: @project, creator: @human, title: "Moved", position: 3)

    assert_raises(ActiveRecord::RecordInvalid) { moved.move_to!(parent: foreign_parent, position: 0) }

    assert_nil moved.reload.parent
    assert_equal 3, moved.position
    assert_equal 7, foreign_parent.reload.position
  end

  test "assigning an agent creates one task-scoped wake event" do
    agent = User.create!(name: "Klaus", kind: :agent)
    task = Task.create!(project: @project, creator: @human, title: "Prepare launch")

    assert_difference "AgentEvent.count", 1 do
      task.assignments.create!(agent: agent, assigned_by: @human)
    end

    event = AgentEvent.last
    assert_equal "task_assigned", event.event_type
    assert_equal agent, event.recipient
    assert_equal task, event.subject.task
    assert_equal task.id, event.payload.dig(:context, :task, :id)
  end

  test "a correlated comment must preserve task event provenance" do
    agent = User.create!(name: "Klaus provenance", kind: :agent)
    other_agent = User.create!(name: "Hermes provenance", kind: :agent)
    task = Task.create!(project: @project, creator: @human, title: "Assigned task")
    other_task = Task.create!(project: @project, creator: @human, title: "Other task")
    event = task.assignments.create!(agent: agent, assigned_by: @human).agent_events.sole

    assert task.comments.new(author: agent, body: "Done", agent_event: event).valid?
    assert_not other_task.comments.new(author: agent, body: "Wrong task", agent_event: event).valid?
    assert_not task.comments.new(author: other_agent, body: "Wrong author", agent_event: event).valid?
  end

  test "mentioning an agent in a human task comment creates a task-scoped wake event" do
    agent = User.create!(name: "Fable Dev", kind: :agent)
    task = Task.create!(project: @project, creator: @human, title: "Bake a cake")

    assert_difference "AgentEvent.count", 1 do
      task.comments.create!(author: @human, body: "Please help @FABLE-DEV with this")
    end

    event = AgentEvent.last
    assert_equal "task_comment_mentioned", event.event_type
    assert_equal agent, event.recipient
    assert_equal task, event.task
    assert_equal "task", event.payload.dig(:context, :origin)
  end

  test "agent-authored task comments do not recursively mention agents" do
    agent = User.create!(name: "Fable Dev", kind: :agent)
    task = Task.create!(project: @project, creator: @human, title: "Bake a cake")

    assert_no_difference "AgentEvent.count" do
      task.comments.create!(author: agent, body: "Passing this to @fable-dev")
    end
  end

  test "acknowledging a task comment mention reacts to the triggering comment" do
    agent = User.create!(name: "Fable Dev", kind: :agent)
    task = Task.create!(project: @project, creator: @human, title: "Bake a cake")
    comment = task.comments.create!(author: @human, body: "@fable-dev please help")
    event = comment.agent_events.sole

    event.acknowledge!

    assert comment.reactions.exists?(author: agent, emoji: "👍")
  end
end
