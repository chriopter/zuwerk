require "test_helper"

class HostedAgentTest < ActiveSupport::TestCase
  setup do
    @identity = User.create!(name: "Builder", kind: :agent, api_token: "agent-token")
  end

  test "belongs to an agent identity and accepts supported runtimes" do
    hosted_agent = HostedAgent.new(user: @identity, runtime: "claude", state: "stopped")

    assert hosted_agent.valid?
    assert_equal "zuwerk-agent-#{@identity.id}", hosted_agent.container_name

    hosted_agent.runtime = "unknown"
    assert_not hosted_agent.valid?
  end

  test "does not allow a human identity" do
    human = User.create!(name: "Human", email: "human-hosted@example.com", password: "password1")

    hosted_agent = HostedAgent.new(user: human, runtime: "codex")

    assert_not hosted_agent.valid?
    assert_includes hosted_agent.errors[:user], "must be an agent"
  end
end
