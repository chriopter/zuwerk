require "test_helper"

class HostedAgents::TerminalSessionTest < ActiveSupport::TestCase
  class FakeExecutor
    attr_reader :commands

    def initialize
      @commands = []
    end

    def run(*argv, input: nil)
      @commands << [ argv, input ]
      "terminal output"
    end
  end

  setup do
    identity = User.create!(name: "Terminal", kind: :agent)
    @hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    @executor = FakeExecutor.new
    @terminal = HostedAgents::TerminalSession.new(@hosted_agent, executor: @executor)
  end

  test "captures only the managed agent tmux pane" do
    assert_equal "terminal output", @terminal.capture
    assert_equal [ "podman", "exec", @hosted_agent.container_name, "tmux", "capture-pane", "-p", "-e", "-t", "agent:0.0", "-S", "-200" ], @executor.commands.last.first
  end

  test "sends literal bounded input through a request-unique tmux buffer" do
    @terminal.write("hello; rm -rf /\n")

    load_command = @executor.commands[-2]
    paste_command = @executor.commands[-1]
    buffer_name = load_command.first.fetch(load_command.first.index("-b") + 1)

    assert_match(/\Azuwerk-terminal-[0-9a-f]{16}\z/, buffer_name)
    assert_equal [ "podman", "exec", "-i", @hosted_agent.container_name, "tmux", "load-buffer", "-b", buffer_name, "-" ], load_command.first
    assert_equal "hello; rm -rf /\n", load_command.last
    assert_equal [ "podman", "exec", @hosted_agent.container_name, "tmux", "paste-buffer", "-b", buffer_name, "-d", "-t", "agent:0.0" ], paste_command.first
  end

  test "uses a distinct buffer for each write" do
    @terminal.write("a")
    first_buffer = @executor.commands[-2].first.fetch(-2)
    @terminal.write("b")
    second_buffer = @executor.commands[-2].first.fetch(-2)

    assert_not_equal first_buffer, second_buffer
  end

  test "rejects oversized input" do
    assert_raises(ArgumentError) { @terminal.write("x" * 4097) }
    assert_empty @executor.commands
  end
end
