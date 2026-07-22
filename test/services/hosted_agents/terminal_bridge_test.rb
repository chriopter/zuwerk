require "test_helper"
require "stringio"

class HostedAgents::TerminalBridgeTest < ActiveSupport::TestCase
  class EofReader
    def readpartial(*) = raise(EOFError)
    def close = nil
    def closed? = false
  end

  class FakeInteractiveExecutor
    attr_reader :argv, :options

    def open(*argv, **options)
      @argv = argv
      @options = options
      [ StringIO.new, EofReader.new, Struct.new(:pid).new(123_456) ]
    end
  end

  test "starts a fresh tmux session when the runtime session disappeared" do
    identity = User.create!(name: "Terminal agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "codex", state: "running", container_id: "container-id")
    executor = FakeInteractiveExecutor.new

    HostedAgents::TerminalBridge.new(hosted_agent, interactive_executor: executor).start(rows: 40, columns: 120) { }

    command = executor.argv.fetch(-2)
    assert_includes command, "tmux has-session -t agent"
    assert_includes command, "tmux new-session -d -s agent -c /workspace 'exec codex'"
    assert_equal true, executor.options[:pgroup]
  end
end
