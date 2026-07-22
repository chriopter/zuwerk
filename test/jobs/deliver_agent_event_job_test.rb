require "test_helper"

class DeliverAgentEventJobTest < ActiveJob::TestCase
  test "duplicate and late jobs never redispatch terminal events" do
    human = User.create!(name: "Terminal Human", email: "terminal@example.com", password: "password1")
    agent = User.create!(name: "Terminal Agent", kind: :agent)
    event = AgentEvent.create!(recipient: agent, subject: Message.create!(author: human, body: "Terminal"), event_type: "mentioned")
    delivered = []
    DeliverAgentEventJob.connector_dispatcher_factory = ->(*) { Struct.new(:delivered) { def deliver = delivered << :connector }.new(delivered) }
    transport = AgentConnectors.registry.register(agent.id) { |_line| }

    %w[completed failed cancelled].each do |state|
      event.update_columns(state: state, finished_at: Time.current)
      DeliverAgentEventJob.perform_now(event)
    end

    assert_empty delivered
  ensure
    DeliverAgentEventJob.connector_dispatcher_factory = ->(candidate) { AgentConnectors::Dispatcher.new(candidate) }
    AgentConnectors.registry.unregister(agent&.id, transport) if agent
  end

  test "a retry may continue only its exact already-running event" do
    human = User.create!(name: "Retry Human", email: "retry@example.com", password: "password1")
    agent = User.create!(name: "Retry Agent", kind: :agent)
    first = AgentEvent.create!(recipient: agent, subject: Message.create!(author: human, body: "First"), event_type: "mentioned")
    second = AgentEvent.create!(recipient: agent, subject: Message.create!(author: human, body: "Second"), event_type: "mentioned")
    first.transition_to!("running")
    delivered = []
    fallback = ->(candidate, **) { Struct.new(:id, :delivered) { def deliver = delivered << id }.new(candidate.id, delivered) }
    transport = AgentConnectors.registry.register(agent.id) { |_line| }
    DeliverAgentEventJob.fallback_delivery_factory = fallback
    DeliverAgentEventJob.perform_now(second)
    DeliverAgentEventJob.perform_now(first)

    assert_equal [ first.id ], delivered
    assert_equal "queued", second.reload.state
  ensure
    DeliverAgentEventJob.connector_dispatcher_factory = ->(candidate) { AgentConnectors::Dispatcher.new(candidate) }
    DeliverAgentEventJob.fallback_delivery_factory = ->(candidate, url:, secret:) { AgentEventDelivery.new(candidate, url: url, secret: secret) }
    AgentConnectors.registry.unregister(agent&.id, transport) if agent
  end

  test "a process-local registry alone cannot route connector delivery" do
    human = User.create!(name: "Dispatch Human", email: "dispatch@example.com", password: "password1")
    agent = User.create!(name: "Dispatch Agent", kind: :agent)
    project = Project.create!(name: "Dispatch Project")
    event = AgentEvent.create!(recipient: agent, subject: Message.create!(author: human, project: project, body: "Dispatch"), event_type: "mentioned")
    transport = AgentConnectors.registry.register(agent.id) { |_line| }
    delivered = []

    fallback = ->(*) { Struct.new(:delivered) { def deliver = delivered << :fallback }.new(delivered) }
    DeliverAgentEventJob.fallback_delivery_factory = fallback
    DeliverAgentEventJob.perform_now(event)

    assert_equal [ :fallback ], delivered
  ensure
    DeliverAgentEventJob.connector_dispatcher_factory = ->(event) { AgentConnectors::Dispatcher.new(event) }
    DeliverAgentEventJob.fallback_delivery_factory = ->(candidate, url:, secret:) { AgentEventDelivery.new(candidate, url: url, secret: secret) }
    AgentConnectors.registry.unregister(agent&.id, transport) if agent
  end
  test "a worker process does not claim or webhook an event owned by a fresh cable connector" do
    human = User.create!(name: "Cross Process Human", email: "cross-process@example.com", password: "password1")
    agent = User.create!(name: "Cross Process Agent", kind: :agent)
    project = Project.create!(name: "Cross Process Project")
    event = AgentEvent.create!(recipient: agent, subject: Message.create!(author: human, project: project, body: "Dispatch externally"), event_type: "mentioned")
    agent.update_columns(connector_connection_id: "cable-process-1", connector_heartbeat_at: Time.current)
    previous_registry = AgentConnectors.registry
    AgentConnectors.registry = AgentConnectors::Registry.new

    DeliverAgentEventJob.perform_now(event)

    assert_equal "queued", event.reload.state
    assert_nil event.accepted_at
  ensure
    AgentConnectors.registry = previous_registry if previous_registry
  end

  test "routes hosted deliveries to their dedicated serialized queue" do
    human = User.create!(name: "Queue Human", email: "queue-human@example.com", password: "password1")
    hosted_user = User.create!(name: "Hosted Queue Agent", kind: :agent)
    HostedAgent.create!(user: hosted_user, runtime: "claude", state: "running")
    external_user = User.create!(name: "External Queue Agent", kind: :agent)
    project = Project.create!(name: "Queue Project")
    message = Message.create!(author: human, project: project, body: "Queue this")

    hosted_event = AgentEvent.create!(recipient: hosted_user, subject: message, event_type: "mentioned")
    external_event = AgentEvent.create!(recipient: external_user, subject: message, event_type: "mentioned")

    assert_equal "hosted_agents", DeliverAgentEventJob.new(hosted_event).queue_name
    assert_equal "default", DeliverAgentEventJob.new(external_event).queue_name
  end
end
