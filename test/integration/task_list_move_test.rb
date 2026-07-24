require "test_helper"

class TaskListMoveTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "listmove@example.com", password: "password1")
    @project = Project.create!(name: "List move")
    @inbox = @project.task_lists.create!(name: "Inbox")
    @launch = @project.task_lists.create!(name: "Launch", position: 1)
    @task = @project.tasks.create!(creator: @human, title: "Move me", task_list: @inbox)

    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "reorder moves a task into another list" do
    patch reorder_project_task_path(@project, @task), params: { task_list_id: @launch.id }, as: :json

    assert_response :no_content
    assert_equal @launch, @task.reload.task_list
  end

  test "reorder rejects a blank task list" do
    patch reorder_project_task_path(@project, @task), params: { task_list_id: "" }, as: :json

    assert_response :unprocessable_entity
    assert_equal @inbox, @task.reload.task_list
  end

  test "lists can be reordered" do
    third = @project.task_lists.create!(name: "Later", position: 2)

    patch reorder_project_task_list_path(@project, third), params: { position: 0 }, as: :json

    assert_response :no_content
    assert_equal [ "Later", "Tasks", "Inbox", "Launch" ], @project.task_lists.order(:position, :id).pluck(:name)
  end

  test "lists from other projects are rejected" do
    foreign = Project.create!(name: "Foreign").task_lists.create!(name: "Nope")

    patch reorder_project_task_path(@project, @task), params: { task_list_id: foreign.id }, as: :json

    assert_response :unprocessable_entity
    assert_equal @inbox, @task.reload.task_list
  end
end
