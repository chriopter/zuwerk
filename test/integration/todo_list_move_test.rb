require "test_helper"

class TodoListMoveTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "listmove@example.com", password: "password1")
    @project = Project.create!(name: "List move")
    @inbox = @project.todo_lists.create!(name: "Inbox")
    @launch = @project.todo_lists.create!(name: "Launch", position: 1)
    @todo = @project.todos.create!(creator: @human, title: "Move me", todo_list: @inbox)

    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "reorder moves a todo into another list" do
    patch reorder_project_todo_path(@project, @todo), params: { todo_list_id: @launch.id }, as: :json

    assert_response :no_content
    assert_equal @launch, @todo.reload.todo_list
  end

  test "reorder detaches a todo when list id is blank" do
    patch reorder_project_todo_path(@project, @todo), params: { todo_list_id: "" }, as: :json

    assert_response :no_content
    assert_nil @todo.reload.todo_list
  end

  test "lists can be reordered" do
    third = @project.todo_lists.create!(name: "Later", position: 2)

    patch reorder_project_todo_list_path(@project, third), params: { position: 0 }, as: :json

    assert_response :no_content
    assert_equal [ "Later", "Inbox", "Launch" ], @project.todo_lists.order(:position).pluck(:name)
  end

  test "lists from other projects are rejected" do
    foreign = Project.create!(name: "Foreign").todo_lists.create!(name: "Nope")

    patch reorder_project_todo_path(@project, @todo), params: { todo_list_id: foreign.id }, as: :json

    assert_response :unprocessable_entity
    assert_equal @inbox, @todo.reload.todo_list
  end
end
