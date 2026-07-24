require "application_system_test_case"

class MentionAutocompleteTest < ApplicationSystemTestCase
  setup do
    @human = User.create!(name: "Ada", email: "mention-ada@example.com", password: "password1")
    @project = Project.create!(name: "Mention QA")
    User.create!(name: "Fable Dev", kind: :agent)
    User.create!(name: "Hermes", kind: :agent)

    visit new_session_path
    fill_in "Email", with: @human.email
    fill_in "Password", with: "password1"
    click_button "Sign in"
    assert_current_path root_path
  end

  test "typing @ suggests agents and Enter inserts the handle" do
    visit chat_project_path(@project)

    find(".composer-input").send_keys("Hey @fab")
    assert_selector ".mention-menu .mention-option", text: /Fable Dev/

    find(".composer-input").send_keys(:enter)
    assert_no_selector ".mention-menu .mention-option"
    assert_equal "Hey @fable-dev ", find(".composer-input").value
  end

  test "arrow keys pick a different match and Escape closes the menu" do
    visit chat_project_path(@project)

    find(".composer-input").send_keys("@")
    assert_selector ".mention-menu .mention-option", count: 2

    find(".composer-input").send_keys(:down, :tab)
    assert_equal "@hermes ", find(".composer-input").value

    find(".composer-input").send_keys("@")
    assert_selector ".mention-menu .mention-option"
    find(".composer-input").send_keys(:escape)
    assert_no_selector ".mention-menu .mention-option"
  end
end
