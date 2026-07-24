require "application_system_test_case"

class CommentMentionTest < ApplicationSystemTestCase
  setup do
    @human = User.create!(name: "Ada", email: "comment-mention@example.com", password: "password1")
    @project = Project.create!(name: "Mention comments")
    @task = @project.tasks.create!(creator: @human, title: "Review")
    User.create!(name: "Fable Dev", kind: :agent)

    visit new_session_path
    fill_in "Email", with: @human.email
    fill_in "Password", with: "password1"
    click_button "Sign in"
    assert_current_path root_path
  end

  test "typing @ in a comment suggests agents from the lexxy prompt" do
    visit project_task_path(@project, @task)

    editor = find("lexxy-editor [contenteditable='true']", wait: 5)
    editor.click
    editor.send_keys("Bitte @fab")

    assert_selector ".lexxy-prompt-menu--visible li", text: /Fable Dev/, wait: 5
    editor.send_keys(:enter)

    assert_includes find("lexxy-editor [contenteditable='true']").text, "@fable-dev"
  end
end
