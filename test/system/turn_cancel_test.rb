require "application_system_test_case"

class TurnCancelTest < ApplicationSystemTestCase
  setup do
    @human = User.create!(name: "Ada", email: "turncancel@example.com", password: "password1")
    @project = Project.create!(name: "Cancel QA")
    @agent = User.create!(name: "Fable Dev", kind: :agent, working_status: true, heartbeat_at: Time.current)

    chat = Chat.find_or_create_by!(project: @project)
    chat.messages.create!(author: @human, body: "@fable-dev go")
    @event = AgentEvent.where(recipient: @agent).order(:id).last
    @event.transition_to!("running")

    visit new_session_path
    fill_in "Email", with: @human.email
    fill_in "Password", with: "password1"
    click_button "Sign in"
    assert_current_path root_path
  end

  test "double click on a working avatar cancels the turn" do
    visit project_chat_path(@project)

    avatar = find(".avatar-stack-item.is-working")
    avatar.click
    assert_selector ".avatar-stack-item.is-confirming"
    assert_equal "running", @event.reload.state

    find(".avatar-stack-item.is-confirming").click
    assert_text "Fable Dev: Turn abgebrochen."
    assert_equal "cancelled", @event.reload.state
  end

  test "single click on a working avatar does not toggle the subscription" do
    visit project_chat_path(@project)

    assert_no_difference -> { ChatSubscription.count } do
      find(".avatar-stack-item.is-working").click
      assert_selector ".avatar-stack-item.is-confirming"
    end
  end
end
