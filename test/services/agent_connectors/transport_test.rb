require "test_helper"

class AgentConnectors::TransportTest < ActiveSupport::TestCase
  test "forwards exact bounded NDJSON in both directions" do
    sent = Queue.new
    transport = AgentConnectors::Transport.new { |line| sent << line }
    line = JSON.generate(jsonrpc: "2.0", id: "scalar-id", result: {}) + "\n"

    transport.receive(line)
    assert_equal line, transport.read_line(timeout: 0.1)
    transport.write_line(line)
    assert_equal line, sent.pop
  end

  test "rejects malformed multiple and oversized JSON lines" do
    transport = AgentConnectors::Transport.new { |_line| }

    assert_raises(AgentConnectors::Transport::ProtocolError) { transport.receive("{}\n{}\n") }
    assert transport.closed?

    oversized = AgentConnectors::Transport.new { |_line| }
    assert_raises(AgentConnectors::Transport::ProtocolError) do
      oversized.receive(JSON.generate(value: "x" * 10.megabytes) + "\n")
    end
  end

  test "disconnect wakes blocked readers and replacement invalidates old transport" do
    registry = AgentConnectors::Registry.new
    first = registry.register(7) { |_line| }
    result = Queue.new
    reader = Thread.new do
      first.read_line
    rescue => error
      result << error
    end

    second = registry.register(7) { |_line| }

    assert_instance_of AgentConnectors::Transport::Disconnected, result.pop
    assert first.closed?
    assert_same second, registry.fetch(7)
  ensure
    reader&.join(1)
  end

  test "fails closed when inbound message count is exhausted" do
    transport = AgentConnectors::Transport.new(max_messages: 2, max_queue_bytes: 1.megabyte) { |_line| }
    2.times { |id| transport.receive(JSON.generate(id: id) + "\n") }
    assert_raises(AgentConnectors::Transport::ProtocolError) { transport.receive("{}\n") }
    assert transport.closed?
    assert_raises(AgentConnectors::Transport::Disconnected) { transport.read_line(timeout: 0.1) }
  end

  test "bounds total bytes and releases accounting after reads" do
    line = JSON.generate(value: "1234567890") + "\n"
    transport = AgentConnectors::Transport.new(max_messages: 100, max_queue_bytes: line.bytesize) { |_line| }
    transport.receive(line)
    assert_equal line, transport.read_line(timeout: 0.1)
    transport.receive(line)
    assert_raises(AgentConnectors::Transport::ProtocolError) { transport.receive(line) }
  end

  test "concurrent producers and consumers do not race queue accounting" do
    transport = AgentConnectors::Transport.new(max_messages: 500, max_queue_bytes: 1.megabyte) { |_line| }
    received = Queue.new
    consumers = 10.times.map { Thread.new { 20.times { received << transport.read_line(timeout: 2) } } }
    producers = 10.times.map do |producer|
      Thread.new { 20.times { |number| transport.receive(JSON.generate(producer: producer, number: number) + "\n") } }
    end
    (producers + consumers).each(&:value)
    assert_equal 200, received.size
    assert_equal 0, transport.queued_messages
    assert_equal 0, transport.queued_bytes
  ensure
    transport&.disconnect
  end
end
