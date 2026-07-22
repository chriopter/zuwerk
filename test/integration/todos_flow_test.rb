require "test_helper"

class TodosFlowTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "ada-todos@example.com", password: "password1")
    @agent = User.create!(name: "Klaus", kind: :agent)
    @project = Project.create!(name: "Todo workspace")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "human opens the form and creates a described child todo at a zero-based position" do
    parent = Todo.create!(project: @project, creator: @human, title: "Parent")

    get new_project_todo_path(@project, parent_id: parent.id)
    assert_response :success
    assert_select "select[name='todo[parent_id]'] option[selected][value='#{parent.id}']"

    post project_todos_path(@project), params: { todo: { title: "Ship hierarchy", description: "Useful context", parent_id: parent.id } }
    todo = Todo.last

    assert_redirected_to project_todo_path(@project, todo)
    assert_equal parent, todo.parent
    assert_equal 0, todo.position
    assert_equal "Useful context", todo.description.to_plain_text
    follow_redirect!
    assert_select ".workspace-sidebar a[href='#{project_todos_path(@project)}']", text: "Tasks"
    assert_select "h1", text: "Ship hierarchy"
    assert_select "lexxy-editor"
  end

  test "human sees validation errors for blank titles and invalid parents" do
    assert_no_difference "Todo.count" do
      post project_todos_path(@project), params: { todo: { title: "", description: "Keep this input" } }
    end
    assert_response :unprocessable_entity
    assert_select "p.text-red-600", text: /Title can't be blank/
    assert_select "input[name='todo[title]']"

    other_project = Project.create!(name: "Other workspace")
    foreign_parent = Todo.create!(project: other_project, creator: @human, title: "Foreign")
    assert_no_difference "Todo.count" do
      post project_todos_path(@project), params: { todo: { title: "Local", parent_id: foreign_parent.id } }
    end
    assert_response :unprocessable_entity
    assert_select "p.text-red-600", text: /Parent is invalid/
  end

  test "human edits reparents completes and reopens a todo" do
    parent = Todo.create!(project: @project, creator: @human, title: "Parent")
    todo = Todo.create!(project: @project, creator: @human, title: "Draft")

    patch project_todo_path(@project, todo), params: { todo: { title: "Edited", description: "Final context", parent_id: parent.id } }
    assert_redirected_to project_todo_path(@project, todo)
    assert_equal [ "Edited", "Final context", parent ], [ todo.reload.title, todo.description.to_plain_text, todo.parent ]

    patch project_todo_path(@project, todo), params: { todo: { status: "in_progress" } }
    assert todo.reload.in_progress?
    patch project_todo_path(@project, todo), params: { todo: { status: "completed" } }
    assert todo.reload.completed?
    patch project_todo_path(@project, todo), params: { todo: { status: "open" } }
    assert todo.reload.open?
  end

  test "human assigns an agent and adds edits and deletes a rich comment" do
    todo = Todo.create!(project: @project, creator: @human, title: "Agent task")

    assert_difference "AgentEvent.count", 1 do
      post project_todo_assignments_path(@project, todo), params: { agent_id: @agent.id }
    end
    assert_redirected_to project_todo_path(@project, todo)

    post project_todo_comments_path(@project, todo), params: { todo_comment: { body: "Initial <strong>context</strong>" } }
    comment = TodoComment.last
    assert_includes comment.body.to_plain_text, "Initial context"

    patch project_todo_comment_path(@project, todo, comment), params: { todo_comment: { body: "Updated context" } }
    assert_equal "Updated context", comment.reload.body.to_plain_text

    assert_difference "TodoComment.count", -1 do
      delete project_todo_comment_path(@project, todo, comment)
    end
  end

  test "blank comments render the todo with action text validation errors" do
    todo = Todo.create!(project: @project, creator: @human, title: "Comment task")

    assert_no_difference "TodoComment.count" do
      post project_todo_comments_path(@project, todo), params: { todo_comment: { body: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "h1", text: todo.title
    assert_select "p.text-red-600", text: /Body can't be blank/
    assert_select "lexxy-editor"
  end

  test "assignment is idempotent and can be removed" do
    todo = Todo.create!(project: @project, creator: @human, title: "Agent task")

    2.times { post project_todo_assignments_path(@project, todo), params: { agent_id: @agent.id } }
    assert_equal [ @agent ], todo.reload.assigned_agents
    assert_equal 1, todo.assignments.count
    assert_equal 1, AgentEvent.where(subject: todo.assignments.sole).count

    assert_difference "TodoAssignment.count", -1 do
      delete project_todo_assignment_path(@project, todo, todo.assignments.sole)
    end
  end

  test "drag reorder updates parent and sibling position inside the project" do
    parent = Todo.create!(project: @project, creator: @human, title: "Parent")
    child = Todo.create!(project: @project, creator: @human, title: "Child")

    patch reorder_project_todo_path(@project, child), params: { parent_id: parent.id, position: 3 }, as: :json

    assert_response :no_content
    assert_equal parent, child.reload.parent
    assert_equal 0, child.position
  end

  test "root reorder never changes root positions in another project" do
    moved = Todo.create!(project: @project, creator: @human, title: "Moved root", position: 4)
    other_project = Project.create!(name: "Other workspace")
    foreign_root = Todo.create!(project: other_project, creator: @human, title: "Foreign root", position: 41)

    patch reorder_project_todo_path(@project, moved), params: { parent_id: "", position: 0 }, as: :json

    assert_response :no_content
    assert_equal 41, foreign_root.reload.position
  end

  test "drag reorder compacts both sibling lists and rejects ancestry cycles" do
    parent = Todo.create!(project: @project, creator: @human, title: "Parent", position: 0)
    child = Todo.create!(project: @project, creator: @human, title: "Child", parent: parent, position: 0)
    sibling = Todo.create!(project: @project, creator: @human, title: "Sibling", position: 1)

    patch reorder_project_todo_path(@project, sibling), params: { parent_id: parent.id, position: 0 }, as: :json

    assert_response :no_content
    assert_equal [ sibling, child ], parent.children.reload.ordered
    assert_equal [ 0, 1 ], parent.children.ordered.pluck(:position)
    assert_equal [ parent ], @project.todos.roots.ordered

    patch reorder_project_todo_path(@project, parent), params: { parent_id: child.id, position: 0 }, as: :json
    assert_response :unprocessable_entity
    assert_nil parent.reload.parent
  end

  test "drag reorder rejects a parent from another project and a missing position" do
    moved = Todo.create!(project: @project, creator: @human, title: "Moved", position: 2)
    other_project = Project.create!(name: "Other drag workspace")
    foreign_parent = Todo.create!(project: other_project, creator: @human, title: "Foreign", position: 9)

    patch reorder_project_todo_path(@project, moved), params: { parent_id: foreign_parent.id, position: 0 }, as: :json
    assert_response :unprocessable_entity

    patch reorder_project_todo_path(@project, moved), params: { parent_id: "" }, as: :json
    assert_response :unprocessable_entity
    assert_nil moved.reload.parent
    assert_equal 2, moved.position
    assert_equal 9, foreign_parent.reload.position
  end
end
