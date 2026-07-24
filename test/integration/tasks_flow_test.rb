require "test_helper"

class TasksFlowTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "ada-tasks@example.com", password: "password1")
    @agent = User.create!(name: "Klaus", kind: :agent)
    @project = Project.create!(name: "Task workspace")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "human opens the form and creates a described child task at a zero-based position" do
    parent = Task.create!(project: @project, creator: @human, title: "Parent")

    get new_project_task_path(@project, parent_id: parent.id)
    assert_response :success
    assert_select "select[name='task[parent_id]'] option[selected][value='#{parent.id}']"

    post project_tasks_path(@project), params: { task: { title: "Ship hierarchy", description: "Useful context", parent_id: parent.id } }
    task = Task.last

    assert_redirected_to project_task_path(@project, task)
    assert_equal parent, task.parent
    assert_equal 0, task.position
    assert_equal "Useful context", task.description.to_plain_text
    follow_redirect!
    assert_select ".workspace-breadcrumb a[href='#{project_path(@project)}']", text: @project.name
    assert_select ".workspace-breadcrumb a[href='#{project_tasks_path(@project)}']", text: "Tasks"
    assert_select ".workspace-breadcrumb span[aria-current='page']", text: "##{task.id}"
    assert_select ".task-title-input[value=?]", "Ship hierarchy"
    assert_select "lexxy-editor"
  end

  test "human sees validation errors for blank titles and invalid parents" do
    assert_no_difference "Task.count" do
      post project_tasks_path(@project), params: { task: { title: "", description: "Keep this input" } }
    end
    assert_response :unprocessable_entity
    assert_select "p.text-red-600", text: /Title can't be blank/
    assert_select "input[name='task[title]']"

    other_project = Project.create!(name: "Other workspace")
    foreign_parent = Task.create!(project: other_project, creator: @human, title: "Foreign")
    assert_no_difference "Task.count" do
      post project_tasks_path(@project), params: { task: { title: "Local", parent_id: foreign_parent.id } }
    end
    assert_response :unprocessable_entity
    assert_select "p.text-red-600", text: /Parent is invalid/
  end

  test "human edits reparents completes and reopens a task" do
    parent = Task.create!(project: @project, creator: @human, title: "Parent")
    task = Task.create!(project: @project, creator: @human, title: "Draft")

    patch project_task_path(@project, task), params: { task: { title: "Edited", description: "Final context", parent_id: parent.id } }
    assert_redirected_to project_task_path(@project, task)
    assert_equal [ "Edited", "Final context", parent ], [ task.reload.title, task.description.to_plain_text, task.parent ]

    patch project_task_path(@project, task), params: { task: { status: "completed" } }
    assert task.reload.completed?
    patch project_task_path(@project, task), params: { task: { status: "completed" } }
    assert task.reload.completed?
    patch project_task_path(@project, task), params: { task: { status: "open" } }
    assert task.reload.open?
  end

  test "human assigns an agent and adds edits and deletes a rich comment" do
    task = Task.create!(project: @project, creator: @human, title: "Agent task")

    assert_difference "AgentEvent.count", 1 do
      post project_task_assignments_path(@project, task), params: { agent_id: @agent.id }
    end
    assert_redirected_to project_task_path(@project, task)

    post project_task_comments_path(@project, task), params: { task_comment: { body: "Initial <strong>context</strong>" } }
    comment = TaskComment.last
    assert_includes comment.body.to_plain_text, "Initial context"

    patch project_task_comment_path(@project, task, comment), params: { task_comment: { body: "Updated context" } }
    assert_equal "Updated context", comment.reload.body.to_plain_text

    assert_difference "TaskComment.count", -1 do
      delete project_task_comment_path(@project, task, comment)
    end
  end

  test "blank comments render the task with action text validation errors" do
    task = Task.create!(project: @project, creator: @human, title: "Comment task")

    assert_no_difference "TaskComment.count" do
      post project_task_comments_path(@project, task), params: { task_comment: { body: "" } }
    end

    assert_response :unprocessable_entity
    assert_select ".task-title-input[value=?]", task.title
    assert_select "p.text-red-600", text: /Body can't be blank/
    assert_select "lexxy-editor"
  end

  test "assignment is idempotent and can be removed" do
    task = Task.create!(project: @project, creator: @human, title: "Agent task")

    2.times { post project_task_assignments_path(@project, task), params: { agent_id: @agent.id } }
    assert_equal [ @agent ], task.reload.assigned_agents
    assert_equal 1, task.assignments.count
    assert_equal 1, AgentEvent.where(subject: task.assignments.sole).count

    assert_difference "TaskAssignment.count", -1 do
      delete project_task_assignment_path(@project, task, task.assignments.sole)
    end
  end

  test "drag reorder updates parent and sibling position inside the project" do
    parent = Task.create!(project: @project, creator: @human, title: "Parent")
    child = Task.create!(project: @project, creator: @human, title: "Child")

    patch reorder_project_task_path(@project, child), params: { parent_id: parent.id, position: 3 }, as: :json

    assert_response :no_content
    assert_equal parent, child.reload.parent
    assert_equal 0, child.position
  end

  test "root reorder never changes root positions in another project" do
    moved = Task.create!(project: @project, creator: @human, title: "Moved root", position: 4)
    other_project = Project.create!(name: "Other workspace")
    foreign_root = Task.create!(project: other_project, creator: @human, title: "Foreign root", position: 41)

    patch reorder_project_task_path(@project, moved), params: { parent_id: "", position: 0 }, as: :json

    assert_response :no_content
    assert_equal 41, foreign_root.reload.position
  end

  test "drag reorder compacts both sibling lists and rejects ancestry cycles" do
    parent = Task.create!(project: @project, creator: @human, title: "Parent", position: 0)
    child = Task.create!(project: @project, creator: @human, title: "Child", parent: parent, position: 0)
    sibling = Task.create!(project: @project, creator: @human, title: "Sibling", position: 1)

    patch reorder_project_task_path(@project, sibling), params: { parent_id: parent.id, position: 0 }, as: :json

    assert_response :no_content
    assert_equal [ sibling, child ], parent.children.reload.ordered
    assert_equal [ 0, 1 ], parent.children.ordered.pluck(:position)
    assert_equal [ parent ], @project.tasks.roots.ordered

    patch reorder_project_task_path(@project, parent), params: { parent_id: child.id, position: 0 }, as: :json
    assert_response :unprocessable_entity
    assert_nil parent.reload.parent
  end

  test "drag reorder rejects a parent from another project and a missing position" do
    moved = Task.create!(project: @project, creator: @human, title: "Moved", position: 2)
    other_project = Project.create!(name: "Other drag workspace")
    foreign_parent = Task.create!(project: other_project, creator: @human, title: "Foreign", position: 9)

    patch reorder_project_task_path(@project, moved), params: { parent_id: foreign_parent.id, position: 0 }, as: :json
    assert_response :unprocessable_entity

    patch reorder_project_task_path(@project, moved), params: { parent_id: "" }, as: :json
    assert_response :unprocessable_entity
    assert_nil moved.reload.parent
    assert_equal 2, moved.position
    assert_equal 9, foreign_parent.reload.position
  end
end
