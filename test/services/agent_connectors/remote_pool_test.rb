require "test_helper"

class AgentConnectors::RemotePoolTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :closed

    def initialize(transport)
      @transport = transport
      @closed = false
    end

    def alive? = !closed && @transport.alive?
    def close = (@closed = true)
  end

  setup do
    AgentConnectors::RemotePool.send(:reset!)
  end

  teardown do
    AgentConnectors::RemotePool.client_factory = ->(transport) { HostedAgents::AcpClient.new(nil, transport: transport) }
    AgentConnectors::RemotePool.send(:reset!)
  end

  test "does not initialize a client while holding the global map mutex" do
    transport = AgentConnectors::Transport.new { |_line| }
    observed = nil
    AgentConnectors::RemotePool.client_factory = lambda do |candidate|
      mutex = AgentConnectors::RemotePool.send(:maps_mutex)
      observed = mutex.try_lock
      mutex.unlock if observed
      FakeClient.new(candidate)
    end

    AgentConnectors::RemotePool.send(:mutex_for, 11).synchronize do
      AgentConnectors::RemotePool.send(:entry_for, 11, transport)
    end

    assert observed, "client initialization held the global map mutex"
  end

  test "keeps a stable per-agent lock across cleanup and replacement" do
    first_transport = AgentConnectors::Transport.new { |_line| }
    second_transport = AgentConnectors::Transport.new { |_line| }
    AgentConnectors::RemotePool.client_factory = ->(transport) { FakeClient.new(transport) }
    lock = AgentConnectors::RemotePool.send(:mutex_for, 12)

    lock.synchronize { AgentConnectors::RemotePool.send(:entry_for, 12, first_transport) }
    AgentConnectors::RemotePool.send(:cleanup, 12, first_transport)
    replacement_lock = AgentConnectors::RemotePool.send(:mutex_for, 12)
    replacement_lock.synchronize { AgentConnectors::RemotePool.send(:entry_for, 12, second_transport) }

    assert_same lock, replacement_lock
  end

  test "disconnect cancels a pending approval and its event" do
    human = User.create!(name: "Pool Human", email: "pool-human@example.com", password: "password1")
    agent = User.create!(name: "Pool Agent", kind: :agent)
    event = AgentEvent.create!(recipient: agent, subject: Message.create!(author: human, body: "Approve"), event_type: "mentioned")
    event.transition_to!("running")
    dead_client = Struct.new(:alive?).new(false)

    result = AgentConnectors::RemotePool.send(
      :await_approval,
      event,
      "permission",
      { "options" => [ { "optionId" => "allow" } ] },
      client: dead_client
    )

    assert_same HostedAgents::AcpClient::PERMISSION_CANCELLED, result
    assert_equal "cancelled", event.agent_approvals.sole.reload.state
    assert_equal "cancelled", event.reload.state
  end

  test "serializes concurrent initialization and replacement per agent" do
    first_transport = AgentConnectors::Transport.new { |_line| }
    second_transport = AgentConnectors::Transport.new { |_line| }
    created = Queue.new
    AgentConnectors::RemotePool.client_factory = lambda do |transport|
      sleep 0.02
      FakeClient.new(transport).tap { |client| created << client }
    end

    threads = [ first_transport, second_transport ].map do |transport|
      Thread.new do
        AgentConnectors::RemotePool.send(:mutex_for, 13).synchronize do
          AgentConnectors::RemotePool.send(:entry_for, 13, transport)
        end
      end
    end
    entries = threads.map(&:value)

    current = AgentConnectors::RemotePool.send(:entries).fetch(13)
    clients = entries.map { |entry| entry.fetch(:client) }
    assert_equal 2, created.size
    assert_equal 1, clients.count(&:closed)
    assert_not current.fetch(:client).closed
    assert_includes [ first_transport, second_transport ], current.fetch(:transport)
  end
end
