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
    assert_select "form[action='#{restart_agent_path(identity)}']"
    assert_select "span", text: /Codex/
  end
end
