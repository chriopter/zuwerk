require "test_helper"

class AgentEventTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @human = User.create!(name: "Human", email: "human@example.com", password: "password1")
    @hermes = User.create!(name: "Hermes", kind: :agent)
    @build_agent = User.create!(name: "Build Agent", kind: :agent)
  end

  test "message creates one chat_message_mentioned event per chat_message_mentioned agent after matching case insensitively" do
    assert_enqueued_jobs 2, only: DeliverAgentEventJob do
      message = ChatMessage.create!(author: @human, project: Project.default, body: "@HERMES please ask @build-agent and @hermes again")
      assert_equal [ @hermes, @build_agent ].sort_by(&:id), message.agent_events.map(&:recipient).sort_by(&:id)
    end
  end

  test "mention requires a complete handle boundary" do
    message = ChatMessage.create!(author: @human, project: Project.default, body: "@hermes2 and x@hermes but not the agent")

    assert_empty message.agent_events
  end

  test "human names do not create chat_message_mentioned events" do
    message = ChatMessage.create!(author: @human, project: Project.default, body: "@human hello")

    assert_empty message.agent_events
  end

  test "agent subscriptions create one project event per selected agent without a mention" do
    project = Project.create!(name: "Alerts")
    project.chat_subscriptions.create!(agent: @hermes)
    project.chat_subscriptions.create!(agent: @build_agent)

    message = ChatMessage.create!(author: @human, project: project, body: "Status update")

    assert_equal [ @hermes, @build_agent ].sort_by(&:id), message.agent_events.map(&:recipient).sort_by(&:id)
    assert message.agent_events.all? { |event| event.payload.dig(:context, :project, :id) == project.id }
  end

  test "agent-authored messages never create mention events" do
    project = Project.create!(name: "Agent chat")
    project.chat_subscriptions.create!(agent: @build_agent)

    message = ChatMessage.create!(author: @hermes, project: project, body: "@build-agent status")

    assert_empty message.agent_events
  end

  test "event-correlated messages must match the recipient event type and project" do
    project = Project.create!(name: "Responses")
    other_project = Project.create!(name: "Other responses")
    source = ChatMessage.create!(author: @human, project: project, body: "@hermes respond")
    event = source.agent_events.sole

    assert ChatMessage.new(author: @hermes, project: project, body: "Done", agent_event: event).valid?
    assert_not ChatMessage.new(author: @build_agent, project: project, body: "Wrong agent", agent_event: event).valid?
    assert_not ChatMessage.new(author: @hermes, project: other_project, body: "Wrong project", agent_event: event).valid?
  end

  test "event uniqueness prevents duplicate recipient and message events" do
    message = ChatMessage.create!(author: @human, project: Project.default, body: "@hermes")
    duplicate = AgentEvent.new(event_type: "chat_message_mentioned", recipient: @hermes, subject: message)

    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "payload contains identifiers but no conversation content" do
    message = ChatMessage.create!(author: @human, project: Project.default, body: "private conversation text @hermes")
    event = message.agent_events.sole
    payload = event.payload

    assert_equal event.public_id, payload[:id]
    assert_equal "chat_message_mentioned", payload[:type]
    assert_equal({ id: @hermes.id, handle: "hermes" }, payload[:recipient])
    assert_equal({ type: "chat_message", id: message.id }, payload[:subject])
    assert_equal({ project: { id: message.project.id, name: message.project.name }, conversation: "chat" }, payload[:context])
    assert_equal event.created_at.iso8601, payload[:occurred_at]
    assert_not_includes payload.to_json, message.body
  end

  test "persists durable state timestamps and only permits valid transitions" do
    event = ChatMessage.create!(author: @human, project: Project.default, body: "@hermes state").agent_events.sole

    assert_equal "queued", event.state
    event.transition_to!("running")
    assert event.started_at?
    event.transition_to!("waiting_for_approval")
    event.transition_to!("running")
    event.transition_to!("completed")
    assert event.finished_at?
    assert_raises(AgentEvent::InvalidTransition) { event.transition_to!("running") }
  end

  test "atomically claims one event per recipient in FIFO order" do
    first = ChatMessage.create!(author: @human, project: Project.default, body: "@hermes first").agent_events.sole
    second = ChatMessage.create!(author: @human, project: Project.default, body: "@hermes second").agent_events.sole

    assert_equal first, AgentEvent.claim_next_for!(@hermes)
    assert_nil AgentEvent.claim_next_for!(@hermes)
    assert_equal "queued", second.reload.state

    first.transition_to!("completed")
    assert_equal second, AgentEvent.claim_next_for!(@hermes)
  end
end
