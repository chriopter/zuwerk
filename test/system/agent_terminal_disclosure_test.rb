require "application_system_test_case"

class AgentTerminalDisclosureTest < ApplicationSystemTestCase
  setup do
    @human = User.create!(name: "Ada", email: "terminal-ada@example.com", password: "password1")
    Project.create!(name: "Terminal QA")
    @agent = User.create!(name: "Terminal Agent", kind: :agent)
    @hosted = HostedAgent.create!(user: @agent, runtime: "codex", state: "running", container_id: "terminal-test")

    visit new_session_path
    fill_in "Email", with: @human.email
    fill_in "Password", with: "password1"
    click_button "Sign in"
    assert_current_path root_path
  end

  test "terminal mounts only while its disclosure is open" do
    visit agent_path(@agent)

    assert_selector ".agent-terminal-disclosure:not([open])"
    assert_no_selector ".xterm"

    find(".agent-terminal-disclosure > summary").click
    assert_selector ".agent-terminal-disclosure[open] .xterm", count: 1

    find(".agent-terminal-disclosure > summary").click
    assert_selector ".agent-terminal-disclosure:not([open])"
    assert_no_selector ".xterm"
    assert_no_selector "[data-terminal-mounted='true']"

    find(".agent-terminal-disclosure > summary").click
    assert_selector ".agent-terminal-disclosure[open] .xterm", count: 1
  end

  test "stopped terminal remains unmounted when opened" do
    @hosted.update!(state: "stopped")
    visit agent_path(@agent)

    find(".agent-terminal-disclosure > summary").click
    assert_selector ".agent-terminal-disclosure[open]"
    assert_no_selector ".xterm"
    assert_no_selector "[data-terminal-mounted='true']"
  end
end
