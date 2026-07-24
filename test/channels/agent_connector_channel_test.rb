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
    assert @agent.reload.external_connector_present?

    perform :receive, type: "acp", line: "{\"jsonrpc\":\"2.0\"}\n"
    assert_equal "{\"jsonrpc\":\"2.0\"}\n", transport.read_line(timeout: 0.1)

    perform :receive, type: "heartbeat"
    assert @agent.reload.heartbeat_at?

    transport.write_line("{\"id\":1}\n")
    assert_equal({ "type" => "acp", "line" => "{\"id\":1}\n" }, transmissions.last)
  ensure
    unsubscribe
    assert_nil @agent.reload.connector_connection_id
  end

  test "passes CLI sequence numbers to the transport" do
    subscribe
    transport = AgentConnectors.registry.fetch(@agent.id)

    perform :receive, type: "acp", sequence: 2, line: "{\"id\":2}\n"
    perform :receive, type: "acp", sequence: 1, line: "{\"id\":1}\n"

    assert_equal "{\"id\":1}\n", transport.read_line(timeout: 0.1)
    assert_equal "{\"id\":2}\n", transport.read_line(timeout: 0.1)
  ensure
    unsubscribe
  end

  test "rejects humans" do
    human = User.create!(name: "No Connector", email: "no-connector@example.com", password: "password1")
    stub_connection current_user: human
    subscribe
    assert subscription.rejected?
  end

  test "connection presence is conditionally cleared so an old disconnect cannot erase its replacement" do
    assert @agent.register_connector!("first-connection")
    assert @agent.register_connector!("second-connection")
    assert_not @agent.clear_connector!("first-connection")
    assert_equal "second-connection", @agent.reload.connector_connection_id
    assert @agent.clear_connector!("second-connection")
    assert_nil @agent.reload.connector_connection_id
  end

  test "registration does not steal an event already claimed by fallback" do
    human = User.create!(name: "Fallback Human", email: "fallback-human@example.com", password: "password1")
    project = Project.create!(name: "Fallback Claim Project")
    event = AgentEvent.create!(recipient: @agent, subject: ChatMessage.create!(author: human, project: project, body: "Fallback"), event_type: "chat_message_mentioned")
    assert_equal event, AgentEvent.claim_for_fallback!(event)

    @agent.register_connector!("late-connector")

    assert_nil event.reload.connector_connection_id
    assert_nil AgentEvent.claim_for_connector!(@agent.id, "late-connector")
  end

  test "cable-owned lifecycle claims FIFO work and dispatches it exactly once" do
    human = User.create!(name: "Cable Human", email: "cable-human@example.com", password: "password1")
    project = Project.create!(name: "Cable Project")
    first = AgentEvent.create!(recipient: @agent, subject: ChatMessage.create!(author: human, project: project, body: "First"), event_type: "chat_message_mentioned")
    second = AgentEvent.create!(recipient: @agent, subject: ChatMessage.create!(author: human, project: project, body: "Second"), event_type: "chat_message_mentioned")
    publications = []
    dispatcher = ->(event) do
      Struct.new(:event, :publications) do
        def deliver
          publications << event.id
          event.update!(delivered_at: Time.current)
          event.transition_to!("completed")
        end
      end.new(event, publications)
    end
    original_registry = AgentConnectors.registry
    cable_registry = AgentConnectors::Registry.new
    AgentConnectors.registry = cable_registry
    transport = cable_registry.register(@agent.id) { |_line| }
    @agent.register_connector!("cable-owner")
    lifecycle = AgentConnectors::Lifecycle.new(agent_id: @agent.id, connection_id: "cable-owner", transport: transport, dispatcher_factory: dispatcher)

    AgentConnectors.registry = AgentConnectors::Registry.new
    DeliverAgentEventJob.perform_now(first)
    assert_equal "queued", first.reload.state
    AgentConnectors.registry = cable_registry

    assert lifecycle.drain_once
    assert lifecycle.drain_once
    assert_not lifecycle.drain_once

    assert_equal [ first.id, second.id ], publications
    assert_equal %w[completed completed], [ first.reload.state, second.reload.state ]
    assert_not AgentEvent.where(recipient: @agent, state: "running").exists?
  ensure
    cable_registry&.unregister(@agent&.id, transport) if transport
    AgentConnectors.registry = original_registry if original_registry
  end

  test "a replaced lifecycle is fenced immediately before dispatch" do
    human = User.create!(name: "Fence Human", email: "fence-human@example.com", password: "password1")
    project = Project.create!(name: "Fence Project")
    event = AgentEvent.create!(recipient: @agent, subject: ChatMessage.create!(author: human, project: project, body: "Fence"), event_type: "chat_message_mentioned")
    delivered = []
    original_registry = AgentConnectors.registry
    registry = AgentConnectors::Registry.new
    AgentConnectors.registry = registry
    old_transport = registry.register(@agent.id) { |_line| }
    @agent.register_connector!("old-owner")
    lifecycle = AgentConnectors::Lifecycle.new(
      agent_id: @agent.id,
      connection_id: "old-owner",
      transport: old_transport,
      dispatcher_factory: ->(*) { Struct.new(:delivered) { def deliver = delivered << :stale }.new(delivered) },
      before_dispatch: -> {
        registry.register(@agent.id) { |_line| }
        @agent.reload.register_connector!("new-owner")
      }
    )

    assert_not lifecycle.drain_once
    assert_empty delivered
    assert_equal "running", event.reload.state
    assert_equal "new-owner", @agent.reload.connector_connection_id
  ensure
    registry&.unregister(@agent&.id)
    AgentConnectors.registry = original_registry if original_registry
  end

  test "lifecycle releases its database checkout before connector IO" do
    human = User.create!(name: "Checkout Human", email: "checkout-human@example.com", password: "password1")
    project = Project.create!(name: "Checkout Project")
    AgentEvent.create!(recipient: @agent, subject: ChatMessage.create!(author: human, project: project, body: "Checkout"), event_type: "chat_message_mentioned")
    original_registry = AgentConnectors.registry
    registry = AgentConnectors::Registry.new
    AgentConnectors.registry = registry
    transport = registry.register(@agent.id) { |_line| }
    @agent.register_connector!("checkout-owner")
    checked_out_during_dispatch = nil
    dispatcher = ->(*) do
      Struct.new(:callback) { def deliver = callback.call }.new(
        -> { checked_out_during_dispatch = ActiveRecord::Base.connection_pool.active_connection? }
      )
    end
    lifecycle = AgentConnectors::Lifecycle.new(agent_id: @agent.id, connection_id: "checkout-owner", transport: transport, dispatcher_factory: dispatcher)

    assert lifecycle.drain_once
    assert_not checked_out_during_dispatch
  ensure
    registry&.unregister(@agent&.id, transport) if transport
    AgentConnectors.registry = original_registry if original_registry
  end
end
