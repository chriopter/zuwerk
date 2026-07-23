require "test_helper"
require "open3"

class HostedAgents::AcpClientTest < ActiveSupport::TestCase
  class FakeTransport
    attr_reader :writes

    def initialize(responses)
      @responses = Queue.new
      responses.each { |response| @responses << JSON.generate(response) + "\n" }
      @writes = []
      @alive = true
    end

    def alive? = @alive
    def read_line(timeout:) = @responses.pop
    def write_line(line) = @writes << JSON.parse(line)
    def disconnect = (@alive = false)
  end
  ADAPTER = <<~'RUBY'
    require "json"
    $stdout.sync = true
    while (line = $stdin.gets)
      message = JSON.parse(line)
      id = message.fetch("id")
      case message.fetch("method")
      when "initialize", "session/set_config_option"
        puts JSON.generate(jsonrpc: "2.0", id: id, result: {})
      when "session/new"
        puts JSON.generate(jsonrpc: "2.0", id: id, result: { sessionId: "session-1" })
      when "session/prompt"
        puts JSON.generate(jsonrpc: "2.0", method: "session/update", params: { update: { sessionUpdate: "agent_message_chunk", content: { text: "Hello" } } })
        puts JSON.generate(jsonrpc: "2.0", id: id, result: { stopReason: "end_turn" })
      end
    end
  RUBY

  class FakeExecutor
    def open_separate(*)
      Open3.popen3(RbConfig.ruby, "-e", ADAPTER)
    end
  end

  test "keeps one adapter process and streams session chunks" do
    identity = User.create!(name: "ACP agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    client = HostedAgents::AcpClient.new(hosted_agent, executor: FakeExecutor.new)
    chunks = []

    session_id = client.new_session
    result = client.prompt(session_id, "Hi") { |chunk| chunks << chunk }

    assert client.alive?
    assert_equal "session-1", session_id
    assert_equal [ "Hello" ], chunks
    assert_equal "end_turn", result.fetch("stopReason")
  ensure
    client&.close
  end

  test "uses the Codex ACP agent mode instead of the unsupported auto mode" do
    identity = User.create!(name: "Codex ACP agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: identity, runtime: "codex", state: "running")
    client = HostedAgents::AcpClient.allocate
    client.instance_variable_set(:@hosted_agent, hosted_agent)

    assert_equal "agent-full-access", client.send(:session_mode)
  end

  test "an autonomous agent stops asking before each action" do
    claude = HostedAgent.create!(user: User.create!(name: "Yolo claude", kind: :agent), runtime: "claude", state: "running", autonomous: true)
    codex = HostedAgent.create!(user: User.create!(name: "Yolo codex", kind: :agent), runtime: "codex", state: "running", autonomous: true)

    [ claude, codex ].each do |hosted_agent|
      client = HostedAgents::AcpClient.allocate
      client.instance_variable_set(:@hosted_agent, hosted_agent)

      assert_equal "bypassPermissions", client.send(:session_mode)
    end
  end

  test "an explicitly requested mode still wins over the autonomous setting" do
    hosted_agent = HostedAgent.create!(user: User.create!(name: "Explicit mode", kind: :agent), runtime: "claude", state: "running", autonomous: true)
    client = HostedAgents::AcpClient.allocate
    client.instance_variable_set(:@hosted_agent, hosted_agent)
    client.instance_variable_set(:@requested_session_mode, "plan")

    assert_equal "plan", client.send(:session_mode)
  end

  test "a supervised agent keeps the negotiated runtime mode" do
    hosted_agent = HostedAgent.create!(user: User.create!(name: "Supervised", kind: :agent), runtime: "claude", state: "running")
    client = HostedAgents::AcpClient.allocate
    client.instance_variable_set(:@hosted_agent, hosted_agent)

    assert_equal "auto", client.send(:session_mode)
  end

  test "accepts an injected transport uses protocol v2 and reports all updates" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: 2, result: { sessionId: "remote-session" } },
      { jsonrpc: "2.0", method: "session/update", params: { update: { sessionUpdate: "tool_call", title: "Run tests" } } },
      { jsonrpc: "2.0", id: 3, result: { stopReason: "end_turn" } }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport)
    updates = []

    session_id = client.new_session
    client.prompt(session_id, "Work", on_update: ->(update) { updates << update })

    assert_equal 2, transport.writes.first.dig("params", "protocolVersion")
    assert_equal "tool_call", updates.sole.fetch("sessionUpdate")
  ensure
    client&.close
  end

  test "retains capabilities and negotiates an advertised mode" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: { protocolVersion: 2, agentCapabilities: { loadSession: true } } },
      { jsonrpc: "2.0", id: 2, result: { sessionId: "remote-session", configOptions: [ { id: "mode", options: [ { value: "auto" } ] } ] } },
      { jsonrpc: "2.0", id: 3, result: {} }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport, session_mode: "auto")

    assert_equal "remote-session", client.new_session
    assert_equal({ "loadSession" => true }, client.agent_capabilities)
    assert_equal [ { "id" => "mode", "options" => [ { "value" => "auto" } ] } ], client.session_capabilities.fetch("configOptions")
    assert_equal "session/set_config_option", transport.writes.third.fetch("method")
  ensure
    client&.close
  end

  test "accepts a single config option object without crashing mode negotiation" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: 2, result: { sessionId: "remote-session", configOptions: { id: "mode", options: { value: "auto" } } } },
      { jsonrpc: "2.0", id: 3, result: {} }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport, session_mode: "auto")

    assert_equal "remote-session", client.new_session
    assert_equal "session/set_config_option", transport.writes.third.fetch("method")
  ensure
    client&.close
  end

  test "does not set or ping a mode unless session new advertises it" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: { agentCapabilities: { promptCapabilities: { image: true } } } },
      { jsonrpc: "2.0", id: 2, result: { sessionId: "claude-session", models: [ "sonnet" ] } }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport, session_mode: "auto")

    assert_equal "claude-session", client.new_session
    assert client.ping("claude-session")
    assert_equal %w[initialize session/new], transport.writes.map { |write| write.fetch("method") }
  ensure
    client&.close
  end

  test "streams text when an ACP agent message chunk uses an array of content blocks" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", method: "session/update", params: { update: { sessionUpdate: "agent_message_chunk", content: [ { type: "text", text: "Hello" }, { type: "image", data: "ignored" }, { type: "text", text: " world" } ] } } },
      { jsonrpc: "2.0", id: 2, result: { stopReason: "end_turn" } }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport)
    chunks = []

    client.prompt("session-1", "Work") { |chunk| chunks << chunk }

    assert_equal [ "Hello world" ], chunks
  ensure
    client&.close
  end

  test "raises a typed pending permission error without auto approval" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: "permission-id", method: "session/request_permission", params: { options: [ { optionId: "allow", kind: "allow_once" } ] } }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport)

    error = assert_raises(HostedAgents::AcpClient::PermissionPending) do
      client.send(:request, "session/prompt", {}, timeout: 1)
    end

    assert_equal "permission-id", error.request_id
    assert_equal 2, transport.writes.length
  ensure
    client&.close
  end

  test "cancelled permission stops the prompt cancels its session and poisons the client" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: "permission", method: "session/request_permission", params: { sessionId: "session-7", options: [ { optionId: "allow" } ] } },
      { jsonrpc: "2.0", id: 2, result: { stopReason: "cancelled" } }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport)

    error = assert_raises(HostedAgents::AcpClient::Error) do
      client.send(:request, "session/prompt", { sessionId: "session-7" }, timeout: 1,
        on_permission: ->(*) { HostedAgents::AcpClient::PERMISSION_CANCELLED })
    end

    assert_match(/cancelled/, error.message)
    assert_equal({ "outcome" => "cancelled" }, transport.writes.third.dig("result", "outcome"))
    assert_equal "session/cancel", transport.writes.fourth.fetch("method")
    assert_equal "session-7", transport.writes.fourth.dig("params", "sessionId")
    assert_not client.alive?
  end

  test "sends an explicitly selected null option without cancelling the prompt" do
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: "permission", method: "session/request_permission", params: { sessionId: "session-7", options: [ { optionId: nil } ] } },
      { jsonrpc: "2.0", id: 2, result: { stopReason: "end_turn" } }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport)

    result = client.send(:request, "session/prompt", { sessionId: "session-7" }, timeout: 1, on_permission: ->(*) { })

    assert_equal({ "outcome" => "selected", "optionId" => nil }, transport.writes.third.dig("result", "outcome"))
    assert_equal "end_turn", result.fetch("stopReason")
    assert client.alive?
  ensure
    client&.close
  end

  test "returns the exact human option to the permission request and continues the same prompt" do
    request_id = { "opaque" => [ 7, "permission" ] }
    transport = FakeTransport.new([
      { jsonrpc: "2.0", id: 1, result: {} },
      { jsonrpc: "2.0", id: request_id, method: "session/request_permission", params: { options: [ { optionId: "reject-exactly" } ] } },
      { jsonrpc: "2.0", id: 2, result: { stopReason: "end_turn" } }
    ])
    client = HostedAgents::AcpClient.new(nil, transport: transport)

    result = client.send(:request, "session/prompt", {}, timeout: 1, on_permission: ->(id, _params) {
      assert_equal request_id, id
      "reject-exactly"
    })

    response = transport.writes.third
    assert_equal request_id, response.fetch("id")
    assert_equal({ "outcome" => "selected", "optionId" => "reject-exactly" }, response.dig("result", "outcome"))
    assert_equal "end_turn", result.fetch("stopReason")
  ensure
    client&.close
  end
end
