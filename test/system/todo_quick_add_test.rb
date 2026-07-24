require "application_system_test_case"

class TodoQuickAddTest < ApplicationSystemTestCase
  setup do
    @human = User.create!(name: "Ada", email: "quickadd@example.com", password: "password1")
    @project = Project.create!(name: "Quick add")
    @list = @project.todo_lists.create!(name: "Inbox")

    visit new_session_path
    fill_in "Email", with: @human.email
    fill_in "Password", with: "password1"
    click_button "Sign in"
    assert_current_path root_path
  end

  test "creating a todo keeps the field open and focused for the next one" do
    visit project_todos_path(@project)

    find(".kanban-create > summary").click
    find(".kanban-create input[type='text']").send_keys("Erstes Todo", :enter)

    assert_selector ".todo-list-row", text: "Erstes Todo"
    assert_selector ".kanban-create[open]"
    active = evaluate_script("document.activeElement.placeholder")
    assert_equal "Titel eingeben…", active

    find(".kanban-create input[type='text']").send_keys("Zweites Todo", :enter)
    assert_selector ".todo-list-row", text: "Zweites Todo"
    assert_equal 2, @list.todos.count
  end
end
