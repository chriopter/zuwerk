require "test_helper"

class HostedAgents::ContainerRuntimeTest < ActiveSupport::TestCase
  FakeCommand = Data.define(:argv, :input)

  class FakeExecutor
    attr_reader :commands

    def initialize(existing: false, mounts: [], env: [ "IS_SANDBOX=1" ])
      @commands = []
      @existing = existing
      @mounts = mounts
      @env = env
    end

    def run(*argv, input: nil)
      @commands << FakeCommand.new(argv, input)
      return "#{@mounts.join("\n")}\n---\n#{@env.join("\n")}\n" if argv.any? { |token| token.include?("Mounts") }

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
    assert_includes command, "--init"
    assert_equal "IS_SANDBOX=1", command[command.index("--env") + 1]
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

  test "provisions without a host mount unless the shared folder is enabled" do
    @runtime.provision

    assert_not_includes @executor.commands.last.argv.join(" "), HostedAgents::ContainerRuntime::SHARED_MOUNT_PATH
  end

  test "mounts the configured host folder read-write when the shared folder is enabled" do
    @hosted_agent.update!(shared_folder: true)

    with_shared_path("/srv/zuwerk") { @runtime.provision }

    command = @executor.commands.last.argv
    assert_includes command, "--volume"
    assert_includes command, "/srv/zuwerk:#{HostedAgents::ContainerRuntime::SHARED_MOUNT_PATH}:rw"
  end

  test "recreates the container so a changed shared folder takes effect" do
    @hosted_agent.update!(shared_folder: true)

    with_shared_path("/srv/zuwerk") { @runtime.recreate }

    assert_equal %W[podman rm --force --time 20 #{@hosted_agent.container_name}], @executor.commands.first.argv
    assert_includes @executor.commands.last.argv, "/srv/zuwerk:#{HostedAgents::ContainerRuntime::SHARED_MOUNT_PATH}:rw"
    assert_equal "running", @hosted_agent.reload.state
  end

  test "recreating keeps the named home and workspace volumes" do
    with_shared_path("/srv/zuwerk") { @runtime.recreate }

    removal = @executor.commands.first.argv
    assert_equal "rm", removal.second
    assert_not_includes removal, "--volumes"
    assert_not_includes removal, "-v"
  end

  test "a container without the shared mount has drifted once the option is enabled" do
    @hosted_agent.update!(shared_folder: true)
    runtime = HostedAgents::ContainerRuntime.new(@hosted_agent, executor: FakeExecutor.new(mounts: [ "/root", "/workspace" ]))

    assert_not runtime.container_current?
  end

  test "a container carrying the shared mount matches the enabled option" do
    @hosted_agent.update!(shared_folder: true)
    mounts = [ "/root", "/workspace", HostedAgents::ContainerRuntime::SHARED_MOUNT_PATH ]
    runtime = HostedAgents::ContainerRuntime.new(@hosted_agent, executor: FakeExecutor.new(mounts: mounts))

    assert runtime.container_current?
  end

  test "a leftover shared mount counts as drift once the option is disabled" do
    mounts = [ "/root", "/workspace", HostedAgents::ContainerRuntime::SHARED_MOUNT_PATH ]
    runtime = HostedAgents::ContainerRuntime.new(@hosted_agent, executor: FakeExecutor.new(mounts: mounts))

    assert_not @hosted_agent.shared_folder?
    assert_not runtime.container_current?
  end

  test "a container missing the sandbox declaration has drifted" do
    runtime = HostedAgents::ContainerRuntime.new(@hosted_agent, executor: FakeExecutor.new(mounts: [ "/root", "/workspace" ], env: [ "PATH=/usr/bin" ]))

    assert_not runtime.container_current?
  end

  test "a supervised container with the sandbox declaration is current" do
    runtime = HostedAgents::ContainerRuntime.new(@hosted_agent, executor: FakeExecutor.new(mounts: [ "/root", "/workspace" ], env: [ "IS_SANDBOX=1" ]))

    assert runtime.container_current?
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

  private
    def with_shared_path(path)
      original = ENV["ZUWERK_AGENT_SHARED_PATH"]
      ENV["ZUWERK_AGENT_SHARED_PATH"] = path
      yield
    ensure
      ENV["ZUWERK_AGENT_SHARED_PATH"] = original
    end
end
