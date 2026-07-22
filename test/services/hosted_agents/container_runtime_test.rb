require "test_helper"

class HostedAgents::ContainerRuntimeTest < ActiveSupport::TestCase
  FakeCommand = Data.define(:argv, :input)

  class FakeExecutor
    attr_reader :commands

    def initialize(existing: false)
      @commands = []
      @existing = existing
    end

    def run(*argv, input: nil)
      @commands << FakeCommand.new(argv, input)
      if argv[1] == "inspect"
        raise HostedAgents::CommandExecutor::CommandError, "missing" unless @existing

        return "running existing-container-id\n"
      end

      "container-id\n"
    end
  end

  setup do
    identity = User.create!(name: "Builder", kind: :agent, api_token: "token")
    @hosted_agent = HostedAgent.create!(user: identity, runtime: "claude")
    @executor = FakeExecutor.new
    @runtime = HostedAgents::ContainerRuntime.new(@hosted_agent, executor: @executor)
  end

  test "provisions a constrained persistent container from the managed image" do
    @runtime.provision

    command = @executor.commands.last.argv
    assert_equal %w[podman run -d], command.first(3)
    assert_includes command, "--name"
    assert_includes command, @hosted_agent.container_name
    assert_includes command, "--restart=unless-stopped"
    assert_includes command, "--memory=4g"
    assert_includes command, "--cpus=2"
    assert_includes command, "zuwerk-agent:latest"
    assert_includes command, "claude"
    assert_equal "container-id", @hosted_agent.reload.container_id
    assert_equal "running", @hosted_agent.state
  end

  test "reconciles an existing managed container when provisioning is retried" do
    executor = FakeExecutor.new(existing: true)
    runtime = HostedAgents::ContainerRuntime.new(@hosted_agent, executor: executor)

    runtime.provision

    assert_equal "existing-container-id", @hosted_agent.reload.container_id
    assert_equal "running", @hosted_agent.state
    assert_equal "podman", executor.commands.first.argv.first
    assert_equal "inspect", executor.commands.first.argv.second
    assert_not executor.commands.any? { |command| command.argv.second == "run" }
  end

  test "lifecycle commands only use the generated container name" do
    @runtime.start
    @runtime.stop
    @runtime.restart

    assert_equal [
      %W[podman start #{@hosted_agent.container_name}],
      %W[podman stop --time 20 #{@hosted_agent.container_name}],
      %W[podman restart --time 20 #{@hosted_agent.container_name}]
    ], @executor.commands.map(&:argv)
  end
end
