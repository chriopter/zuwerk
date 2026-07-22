require "test_helper"

class AgentTerminalChannelTest < ActionCable::Channel::TestCase
  class FakeRuntime
    attr_reader :provisioned

    def initialize(running: true)
      @running = running
    end

    def running? = @running

    def provision
      @provisioned = true
      @running = true
    end
  end

  class FakeBridge
    attr_reader :writes, :sizes, :start_size

    def initialize
      @writes = []
      @sizes = []
    end

    def start(rows:, columns:)
      @start_size = [ rows, columns ]
      yield "ready output"
      self
    end

    def write(data)
      @writes << data
    end

    def resize(rows:, columns:)
      @sizes << [ rows, columns ]
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end
  end

  setup do
    @human = User.create!(name: "Ada", email: "cable-ada@example.com", password: "password1")
    @identity = User.create!(name: "Builder", kind: :agent)
    @hosted_agent = HostedAgent.create!(user: @identity, runtime: "claude", state: "running", container_id: "container-id")
    @bridge = FakeBridge.new
    stub_connection current_user: @human
    AgentTerminalChannel.bridge_factory = ->(_hosted_agent) { @bridge }
    AgentTerminalChannel.runtime_factory = ->(_hosted_agent) { FakeRuntime.new }
  end

  teardown do
    AgentTerminalChannel.bridge_factory = ->(hosted_agent) { HostedAgents::TerminalBridge.new(hosted_agent) }
    AgentTerminalChannel.runtime_factory = ->(hosted_agent) { HostedAgents::ContainerRuntime.new(hosted_agent) }
  end

  test "streams terminal output and accepts input and resize messages" do
    subscribe agent_id: @identity.id, rows: 42, columns: 120

    assert_not subscription.rejected?
    assert_equal [ 42, 120 ], @bridge.start_size
    perform :receive, { "type" => "input", "data" => "hello" }
    perform :receive, { "type" => "resize", "rows" => 40, "columns" => 120 }
    assert_equal [ "hello" ], @bridge.writes
    assert_equal [ [ 40, 120 ] ], @bridge.sizes
  end

  test "rejects stopped agents" do
    @hosted_agent.update!(state: "stopped")

    subscribe agent_id: @identity.id

    assert subscription.rejected?
  end

  test "repairs a stale error state when the real container is running" do
    @hosted_agent.update!(state: "error", last_error: "restart race")

    subscribe agent_id: @identity.id, rows: 42, columns: 120

    assert_not subscription.rejected?
    assert_equal "running", @hosted_agent.reload.state
    assert_nil @hosted_agent.last_error
  end

  test "reprovisions an error-state agent when its container is not running" do
    runtime = FakeRuntime.new(running: false)
    AgentTerminalChannel.runtime_factory = ->(_hosted_agent) { runtime }
    @hosted_agent.update!(state: "error", last_error: "container disappeared")

    subscribe agent_id: @identity.id, rows: 42, columns: 120

    assert_not subscription.rejected?
    assert runtime.provisioned
  end
end
