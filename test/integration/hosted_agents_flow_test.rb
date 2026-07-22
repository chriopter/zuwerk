require "test_helper"

class HostedAgentsFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @human = User.create!(name: "Ada", email: "hosted-ada@example.com", password: "password1")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "creates a persistent hosted Claude agent and queues provisioning" do
    assert_enqueued_with(job: ProvisionHostedAgentJob) do
      assert_difference [ "User.agent.count", "HostedAgent.count" ], 1 do
        post agents_path, params: { agent: { name: "Builder", runtime: "claude" } }
      end
    end

    hosted_agent = HostedAgent.last
    assert_redirected_to agent_path(hosted_agent.user)
    assert_equal "Builder", hosted_agent.user.name
    assert_equal "claude", hosted_agent.runtime
    assert_equal "provisioning", hosted_agent.state
  end

  test "rejects unsupported runtimes without creating an identity" do
    assert_no_difference [ "User.count", "HostedAgent.count" ] do
      post agents_path, params: { agent: { name: "Builder", runtime: "shell" } }
    end

    assert_response :unprocessable_entity
  end

  test "shows the hosted agent cockpit" do
    identity = User.create!(name: "Reviewer", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "codex", state: "running", container_id: "container-id")

    get agent_path(identity)

    assert_response :success
    assert_select "[data-terminal-agent-id='#{identity.id}']"
    assert_select ".terminal-cockpit-fullscreen", count: 0
    assert_select ".terminal-screen-compact"
    assert_select ".agent-overview-grid"
    assert_select ".terminal-titlebar", text: /live websocket/
    assert_select "form[action='#{restart_agent_path(identity)}']"
    assert_select ".agent-detail-header p", text: /Codex/
    assert_select "[data-chat-bridge-status]", text: /Not connected/
    assert_select "a[href='#{new_agent_invitation_path}']", text: /Create invitation link/

    hosted_agent.update!(bridge_connected_at: Time.current, bridge_last_error: nil)
    get agent_path(identity)
    assert_select "[data-chat-bridge-status]", text: /Connected/
    assert_select ".agent-overview-card a[href='#{new_agent_invitation_path}']", count: 0

    hosted_agent.update!(state: "stopped")
    get agent_path(identity)
    assert_select "[data-chat-bridge-status]", text: /Not connected/
    assert_select "[data-terminal-enabled='false']"
  end

  test "queues start stop and restart requests for the selected hosted agent" do
    identity = User.create!(name: "Operator", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "codex", state: "running")

    %w[start stop restart].each do |action|
      assert_enqueued_with(job: ManageHostedAgentJob, args: [ hosted_agent, action ]) do
        post public_send("#{action}_agent_path", identity)
      end
      assert_redirected_to agent_path(identity)
    end
  end

  test "links todo-specific cloud sessions back to their todo" do
    identity = User.create!(name: "Todo worker", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "codex", state: "running")
    project = Project.create!(name: "Delivery")
    todo = project.todos.create!(creator: @human, title: "Ship the release")
    hosted_agent.sessions.create!(origin: todo, external_session_id: "todo-session")

    get agent_path(identity)

    assert_response :success
    assert_select "[data-cloud-session] a[href='#{project_todo_path(project, todo)}']", text: todo.title
    assert_select "[data-cloud-session] small", text: "Todo"
  end
end
