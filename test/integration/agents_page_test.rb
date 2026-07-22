require "test_helper"

class AgentsPageTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "ada@example.com", password: "password1", kind: :human)
    @agent = User.create!(name: "Hermes", kind: :agent, working_status: true, working_label: "Reviewing project context", heartbeat_at: Time.current)
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "lists connected CLI agents and previews server-hosted environments" do
    get agents_path

    assert_response :success
    assert_select "h1", "Agents"
    assert_select ".workspace-sidebar"
    assert_select ".sidebar-channel-active", text: /Agents/
    assert_select "[data-agent-id='#{@agent.id}']", text: /Hermes/
    assert_select "[data-agent-origin='external']", text: /Connected via CLI/
    assert_select "[data-agent-origin='hosted']", text: /On this server/
    assert_select "a[href='#{new_agent_invitation_path}']", text: /Add agent/
  end

  test "external agents redirect back to the agents list" do
    get agent_path(@agent)

    assert_redirected_to agents_path
  end

  test "requires a signed-in human" do
    delete session_path
    get agents_path

    assert_redirected_to new_session_path
  end
end
