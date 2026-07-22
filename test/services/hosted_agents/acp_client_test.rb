require "test_helper"
require "open3"

class HostedAgents::AcpClientTest < ActiveSupport::TestCase
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
end
