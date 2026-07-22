require "test_helper"

class HostedAgents::StartupReconcilerTest < ActiveSupport::TestCase
  class FakeRuntime
    attr_reader :provisioned

    def initialize(running:)
      @running = running
    end

    def running? = @running
    def provision = @provisioned = true
  end

  class FakeProvisioner
    attr_reader :called
    def call = @called = true
  end

  test "starts expected agents that are not actually running and configures the CLI" do
    identity = User.create!(name: "Boot agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    runtime = FakeRuntime.new(running: false)
    provisioner = FakeProvisioner.new

    HostedAgents::StartupReconciler.call(
      scope: HostedAgent.where(id: hosted_agent.id),
      runtime_factory: ->(_agent) { runtime },
      provisioner_factory: ->(_agent) { provisioner }
    )

    assert runtime.provisioned
    assert provisioner.called
  end

  test "configures already running agents without reprovisioning the container" do
    identity = User.create!(name: "Live agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    runtime = FakeRuntime.new(running: true)
    provisioner = FakeProvisioner.new

    HostedAgents::StartupReconciler.call(
      scope: HostedAgent.where(id: hosted_agent.id),
      runtime_factory: ->(_agent) { runtime },
      provisioner_factory: ->(_agent) { provisioner }
    )

    assert_not runtime.provisioned
    assert provisioner.called
  end
end
