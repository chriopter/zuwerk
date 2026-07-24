require "test_helper"

class AgentConnectors::AcpClientTest < ActiveSupport::TestCase
  class FakeTransport
    attr_reader :writes

    def initialize(responses)
      @responses = Queue.new
      responses.each { |response| @responses << JSON.generate(response) + "\n" }
      @writes = []
      @alive = true
    end

    def alive? = @alive
    def read_line(timeout:)
      @responses.pop(true)
    rescue ThreadError
      raise AgentConnectors::Transport::Error, "timed out"
    end
    def write_line(line) = @writes << JSON.parse(line)
    def disconnect = (@alive = false)
  end

  test "initializes ACP v2 and streams updates" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: { agentCapabilities: { loadSession: true } } },
      { jsonrpc: "2.0", id: 2, result: { sessionId: "remote-session" } },
      { jsonrpc: "2.0", method: "session/update", params: { update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "Hello" } } } },
      { jsonrpc: "2.0", id: 3, result: { stopReason: "end_turn" } }
    ])
    client = AgentConnectors::AcpClient.new(transport:)
    chunks = []

    session_id = client.new_session
    result = client.prompt(session_id, "Work") { |chunk| chunks << chunk }

    assert_equal 2, transport.writes.first.dig("params", "protocolVersion")
    assert_equal({ "loadSession" => true }, client.agent_capabilities)
    assert_equal [ "Hello" ], chunks
    assert_equal "end_turn", result.fetch("stopReason")
  ensure
    client&.close
  end

  test "reports the current advertised model and follows config updates" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      {
        jsonrpc: "2.0",
        id: 2,
        result: {
          sessionId: "remote-session",
          configOptions: [
            { id: "model", currentValue: "fable", options: [ { value: "fable", name: "Fable" }, { value: "sonnet", name: "Sonnet" } ] }
          ]
        }
      },
      {
        jsonrpc: "2.0",
        method: "session/update",
        params: {
          update: {
            sessionUpdate: "config_option_update",
            configOptions: [
              { id: "model", currentValue: "sonnet", options: [ { value: "fable", name: "Fable" }, { value: "sonnet", name: "Sonnet" } ] }
            ]
          }
        }
      },
      { jsonrpc: "2.0", id: 3, result: { stopReason: "end_turn" } }
    ])
    client = AgentConnectors::AcpClient.new(transport:)

    client.new_session
    assert_equal "Fable", client.current_model_name
    client.prompt("remote-session", "Work")
    assert_equal "Sonnet", client.current_model_name
  ensure
    client&.close
  end

  test "negotiates an advertised session mode" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: 2, result: { sessionId: "remote-session", modes: { availableModes: [ { id: "bypassPermissions" } ] } } },
      { jsonrpc: "2.0", id: 3, result: {} }
    ])
    client = AgentConnectors::AcpClient.new(transport:, session_mode: "bypassPermissions")

    assert_equal "remote-session", client.new_session
    assert_equal "session/set_mode", transport.writes.third.fetch("method")
    assert_equal "bypassPermissions", transport.writes.third.dig("params", "modeId")
  ensure
    client&.close
  end

  test "leaves an unsupported session mode untouched" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: 2, result: { sessionId: "remote-session", modes: { availableModes: [ { id: "default" } ] } } }
    ])
    client = AgentConnectors::AcpClient.new(transport:, session_mode: "bypassPermissions")

    client.new_session

    assert_equal %w[initialize session/new], transport.writes.map { |write| write.fetch("method") }
  ensure
    client&.close
  end

  test "fails closed when permission is cancelled" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", method: "session/request_permission", id: 99, params: { sessionId: "remote-session", options: [] } }
    ])
    client = AgentConnectors::AcpClient.new(transport:)

    error = assert_raises(AgentConnectors::AcpClient::Error) do
      client.prompt("remote-session", "Work", on_permission: ->(*) { AgentConnectors::AcpClient::PERMISSION_CANCELLED })
    end

    assert_match(/cancelled/, error.message)
    assert_not client.alive?
  end
end
