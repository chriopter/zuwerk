require "test_helper"

class HostedAgents::StartupReconcilerTest < ActiveSupport::TestCase
  class FakeRuntime
    attr_reader :provisioned

    def initialize(running:)
      @running = running
    end

    def running?
      @running
    end

    def provision
      @provisioned = true
    end
  end

  test "starts expected agents that are not actually running" do
    identity = User.create!(name: "Boot agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    runtime = FakeRuntime.new(running: false)

    HostedAgents::StartupReconciler.call(
      scope: HostedAgent.where(id: hosted_agent.id),
      runtime_factory: ->(_agent) { runtime }
    )

    assert runtime.provisioned
  end

  test "does not touch already running agents" do
    identity = User.create!(name: "Live agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    runtime = FakeRuntime.new(running: true)

    HostedAgents::StartupReconciler.call(
      scope: HostedAgent.where(id: hosted_agent.id),
      runtime_factory: ->(_agent) { runtime }
    )

    assert_not runtime.provisioned
  end
end
