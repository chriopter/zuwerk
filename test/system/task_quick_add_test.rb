require "application_system_test_case"

class TaskQuickAddTest < ApplicationSystemTestCase
  setup do
    @human = User.create!(name: "Ada", email: "quickadd@example.com", password: "password1")
    @project = Project.create!(name: "Quick add")
    @list = @project.task_lists.create!(name: "Inbox")

    visit new_session_path
    fill_in "Email", with: @human.email
    fill_in "Password", with: "password1"
    click_button "Sign in"
    assert_current_path root_path
  end

  test "creating a task keeps the field open and focused for the next one" do
    visit project_tasks_path(@project)

    within ".task-list-card[aria-label='Inbox']" do
      find(".kanban-create > summary").click
      find(".kanban-create input[type='text']").send_keys("First task", :enter)

      assert_selector ".task-list-row", text: "First task"
      assert_selector ".kanban-create[open]"
      active = evaluate_script("document.activeElement.placeholder")
      assert_equal "Titel eingeben…", active

      find(".kanban-create input[type='text']").send_keys("Second task", :enter)
      assert_selector ".task-list-row", text: "Second task"
    end
    assert_equal 2, @list.tasks.count
  end
end
