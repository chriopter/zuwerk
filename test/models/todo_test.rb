require "test_helper"

class TodoTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Launch")
    @human = User.create!(name: "Ada", email: "ada@example.com", password: "password1")
  end

  test "todo belongs to one project and stores a rich description" do
    todo = Todo.create!(project: @project, creator: @human, title: "Prepare launch", description: "**Ready** for review")

    assert_equal @project, todo.project
    assert_equal @human, todo.creator
    assert todo.open?
    assert_includes todo.description.to_plain_text, "Ready"
  end

  test "todo title is required and status can be completed" do
    todo = Todo.new(project: @project, creator: @human)

    assert_not todo.valid?
    todo.update(title: "Prepare launch", status: :completed)
    assert todo.completed?
  end

  test "comments belong to the todo and store rich text" do
    todo = Todo.create!(project: @project, creator: @human, title: "Prepare launch")
    comment = todo.comments.create!(author: @human, body: "Looks <strong>good</strong>")

    assert_equal @human, comment.author
    assert_includes comment.body.to_plain_text, "Looks good"
  end

  test "empty comments are rejected" do
    todo = Todo.create!(project: @project, creator: @human, title: "Prepare launch")

    assert_not todo.comments.new(author: @human, body: "").valid?
  end

  test "todos form an ordered ancestry tree inside their project" do
    parent = Todo.create!(project: @project, creator: @human, title: "Launch", position: 1)
    later = Todo.create!(project: @project, creator: @human, title: "Later", parent: parent, position: 2)
    earlier = Todo.create!(project: @project, creator: @human, title: "Earlier", parent: parent, position: 1)

    assert_equal parent, earlier.parent
    assert_equal [ earlier, later ], parent.children.ordered
    assert_equal 1, earlier.depth
  end

  test "moving between parents compacts both sibling lists and inserts at the requested position" do
    parent = Todo.create!(project: @project, creator: @human, title: "Parent", position: 0)
    first = Todo.create!(project: @project, creator: @human, title: "First", parent: parent, position: 0)
    second = Todo.create!(project: @project, creator: @human, title: "Second", parent: parent, position: 1)
    moved = Todo.create!(project: @project, creator: @human, title: "Moved", position: 1)

    moved.move_to!(parent: parent, position: 1)

    assert_equal [ [ first.id, 0 ], [ moved.id, 1 ], [ second.id, 2 ] ], parent.children.ordered.pluck(:id, :position)
    assert_equal [ [ parent.id, 0 ] ], @project.todos.roots.ordered.pluck(:id, :position)
  end

  test "an invalid move rolls back hierarchy and positions" do
    parent = Todo.create!(project: @project, creator: @human, title: "Parent", position: 0)
    child = Todo.create!(project: @project, creator: @human, title: "Child", parent: parent, position: 0)
    sibling = Todo.create!(project: @project, creator: @human, title: "Sibling", position: 1)

    assert_raises(ActiveRecord::RecordInvalid) { parent.move_to!(parent: child, position: 0) }

    assert_nil parent.reload.parent
    assert_equal [ [ parent.id, 0 ], [ sibling.id, 1 ] ], @project.todos.roots.ordered.pluck(:id, :position)
    assert_equal [ [ child.id, 0 ] ], parent.children.ordered.pluck(:id, :position)
  end

  test "a move to a parent in another project is rejected without changing either project" do
    other_project = Project.create!(name: "Other")
    foreign_parent = Todo.create!(project: other_project, creator: @human, title: "Foreign", position: 7)
    moved = Todo.create!(project: @project, creator: @human, title: "Moved", position: 3)

    assert_raises(ActiveRecord::RecordInvalid) { moved.move_to!(parent: foreign_parent, position: 0) }

    assert_nil moved.reload.parent
    assert_equal 3, moved.position
    assert_equal 7, foreign_parent.reload.position
  end

  test "assigning an agent creates one todo-scoped wake event" do
    agent = User.create!(name: "Klaus", kind: :agent)
    todo = Todo.create!(project: @project, creator: @human, title: "Prepare launch")

    assert_difference "AgentEvent.count", 1 do
      todo.assignments.create!(agent: agent, assigner: @human)
    end

    event = AgentEvent.last
    assert_equal "todo_assigned", event.event_type
    assert_equal agent, event.recipient
    assert_equal todo, event.subject.todo
    assert_equal todo.id, event.payload.dig(:context, :todo, :id)
  end

  test "a correlated comment must preserve todo event provenance" do
    agent = User.create!(name: "Klaus provenance", kind: :agent)
    other_agent = User.create!(name: "Hermes provenance", kind: :agent)
    todo = Todo.create!(project: @project, creator: @human, title: "Assigned todo")
    other_todo = Todo.create!(project: @project, creator: @human, title: "Other todo")
    event = todo.assignments.create!(agent: agent, assigner: @human).agent_events.sole

    assert todo.comments.new(author: agent, body: "Done", agent_event: event).valid?
    assert_not other_todo.comments.new(author: agent, body: "Wrong todo", agent_event: event).valid?
    assert_not todo.comments.new(author: other_agent, body: "Wrong author", agent_event: event).valid?
  end
end
