require "test_helper"

class AcpFakeWireIntegrationTest < ActiveSupport::TestCase
  RUNTIMES = {
    "Hermes" => { mode: "auto", advertise_mode: true },
    "Claude" => { mode: "auto", advertise_mode: false },
    "Codex" => { mode: "agent-full-access", advertise_mode: true }
  }.freeze

  RUNTIMES.each do |runtime, config|
    test "real ACP client and bounded transport complete the #{runtime} fake wire lifecycle" do
      outbound = Queue.new
      transport = AgentConnectors::Transport.new { |line| outbound << line }
      permission_id = { "runtime" => runtime, "sequence" => [ 7, nil ] }
      observed = Queue.new
      adapter = Thread.new do
        prompt_id = nil
        loop do
          message = JSON.parse(outbound.pop)
          observed << message
          case message["method"]
          when "initialize"
            transport.receive(response(message, agentCapabilities: { loadSession: true }))
          when "session/new"
            result = { sessionId: "#{runtime.downcase}-session" }
            if config[:advertise_mode]
              result[:configOptions] = [ { id: "mode", options: [ { value: config[:mode] } ] } ]
            end
            transport.receive(response(message, result))
          when "session/set_config_option"
            transport.receive(response(message, {}))
          when "session/prompt"
            prompt_id = message.fetch("id")
            transport.receive(notification("session/update", update: { sessionUpdate: "tool_call", title: "Run tests" }))
            transport.receive(JSON.generate(jsonrpc: "2.0", id: permission_id, method: "session/request_permission", params: {
              sessionId: "#{runtime.downcase}-session", options: [ { optionId: { decision: "allow", runtime: runtime } } ]
            }) + "\n")
          else
            if message["id"] == permission_id
              transport.receive(response({ "id" => prompt_id }, stopReason: "end_turn"))
              break
            end
          end
        end
      end
      client = AgentConnectors::AcpClient.new(transport:, session_mode: config[:mode])
      updates = []
      session_id = client.new_session
      result = client.prompt(
        session_id,
        "Run the integration",
        on_update: ->(update) { updates << update },
        on_permission: ->(id, _params) {
          assert_equal permission_id, id
          { "decision" => "allow", "runtime" => runtime }
        }
      )

      assert_equal "#{runtime.downcase}-session", session_id
      assert_equal "tool_call", updates.sole.fetch("sessionUpdate")
      assert_equal "end_turn", result.fetch("stopReason")
      adapter.join(1)
      messages = drain(observed)
      methods = messages.filter_map { |message| message["method"] }
      assert_equal [ "initialize", "session/new", *(config[:advertise_mode] ? [ "session/set_config_option" ] : []), "session/prompt" ], methods
      permission_response = messages.find { |message| message["id"] == permission_id }
      assert_equal({ "decision" => "allow", "runtime" => runtime }, permission_response.dig("result", "outcome", "optionId"))
    ensure
      client&.close
      transport&.disconnect
      adapter&.join(1)
      adapter&.kill if adapter&.alive?
    end
  end

  test "malformed input and disconnect fail closed and wake a real ACP client" do
    malformed = AgentConnectors::Transport.new { |_line| }
    assert_raises(AgentConnectors::Transport::ProtocolError) { malformed.receive("not-json\n") }
    assert malformed.closed?

    outbound = Queue.new
    disconnected = AgentConnectors::Transport.new { |line| outbound << line }
    adapter = Thread.new do
      initialize_request = JSON.parse(outbound.pop)
      disconnected.receive(response(initialize_request, agentCapabilities: {}))
      outbound.pop
      disconnected.disconnect
    end
    client = AgentConnectors::AcpClient.new(transport: disconnected)
    error = assert_raises(AgentConnectors::AcpClient::Error) { client.new_session }
    assert_match(/disconnected/, error.message)
  ensure
    client&.close
    adapter&.join(1)
  end

  private
    def response(request, result)
      JSON.generate(jsonrpc: "2.0", id: request.fetch("id"), result: result) + "\n"
    end

    def notification(method, params)
      JSON.generate(jsonrpc: "2.0", method: method, params: params) + "\n"
    end

    def drain(queue)
      values = []
      values << queue.pop(true) while true
    rescue ThreadError
      values
    end
end
