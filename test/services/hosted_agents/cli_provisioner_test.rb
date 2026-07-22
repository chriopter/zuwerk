require "test_helper"

class HostedAgents::CliProvisionerTest < ActiveSupport::TestCase
  class FakeExecutor
    attr_reader :calls, :copied_config, :mode

    def initialize(existing_config: nil)
      @calls = []
      @existing_config = existing_config
    end

    def run(*argv, **)
      @calls << argv
      if argv.last == "/root/.config/zuwerk/config.json" && argv[-2] == "cat"
        raise HostedAgents::CommandExecutor::CommandError, "missing" unless @existing_config

        return JSON.generate(@existing_config)
      end
      if argv[0, 2] == [ "podman", "cp" ]
        @copied_config = File.read(argv[2])
        @mode = File.stat(argv[2]).mode & 0o777
      end
      ""
    end
  end

  test "issues one token and copies a private CLI config without putting the token in argv" do
    identity = User.create!(name: "CLI agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    executor = FakeExecutor.new

    HostedAgents::CliProvisioner.new(hosted_agent, executor: executor, server: "http://internal:3100").call

    config = JSON.parse(executor.copied_config)
    assert_equal "http://internal:3100", config.fetch("server_url")
    token = config.fetch("api_token")
    assert_equal User.digest(token), identity.reload.api_token_digest
    assert_equal 0o600, executor.mode
    assert executor.calls.flatten.none? { |argument| argument.include?(token) }
    assert_includes executor.calls, [ "podman", "exec", hosted_agent.container_name, "mkdir", "-p", "/root/.config/zuwerk" ]
    copy_call = executor.calls.find { |call| call[0, 2] == [ "podman", "cp" ] }
    assert_equal "#{hosted_agent.container_name}:/root/.config/zuwerk/config.json", copy_call.last
    assert_includes executor.calls, [ "podman", "exec", hosted_agent.container_name, "chmod", "0600", "/root/.config/zuwerk/config.json" ]
  end

  test "does not rotate an existing matching configuration" do
    identity = User.create!(name: "Configured agent", kind: :agent, api_token: "existing-token")
    hosted_agent = HostedAgent.create!(user: identity, runtime: "codex", state: "running")
    executor = FakeExecutor.new(existing_config: { server_url: "http://internal:3100", api_token: "existing-token" })

    HostedAgents::CliProvisioner.new(hosted_agent, executor: executor, server: "http://internal:3100").call

    assert_equal 1, executor.calls.size
    assert_equal User.digest("existing-token"), identity.reload.api_token_digest
  end

  test "securely rotates a stale configuration" do
    identity = User.create!(name: "Stale agent", kind: :agent, api_token: "old-token")
    hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    executor = FakeExecutor.new(existing_config: { server_url: "http://internal:3100", api_token: "wrong-token" })

    HostedAgents::CliProvisioner.new(hosted_agent, executor: executor, server: "http://internal:3100").call

    token = JSON.parse(executor.copied_config).fetch("api_token")
    refute_equal "old-token", token
    assert_equal User.digest(token), identity.reload.api_token_digest
    assert executor.calls.flatten.none? { |argument| argument.include?(token) }
  end
end
