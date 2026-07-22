require "test_helper"

class AgentConnectorChannelTest < ActionCable::Channel::TestCase
  setup do
    @agent = User.create!(name: "Channel Agent", kind: :agent)
    stub_connection current_user: @agent
    AgentConnectors.registry.unregister(@agent.id)
  end

  test "registers one transport forwards messages and records heartbeat" do
    subscribe
    assert subscription.confirmed?
    transport = AgentConnectors.registry.fetch(@agent.id)

    perform :receive, type: "acp", line: "{\"jsonrpc\":\"2.0\"}\n"
    assert_equal "{\"jsonrpc\":\"2.0\"}\n", transport.read_line(timeout: 0.1)

    perform :receive, type: "heartbeat"
    assert @agent.reload.heartbeat_at?

    transport.write_line("{\"id\":1}\n")
    assert_equal({ "type" => "acp", "line" => "{\"id\":1}\n" }, transmissions.last)
  ensure
    unsubscribe
  end

  test "rejects humans" do
    human = User.create!(name: "No Connector", email: "no-connector@example.com", password: "password1")
    stub_connection current_user: human
    subscribe
    assert subscription.rejected?
  end
end
