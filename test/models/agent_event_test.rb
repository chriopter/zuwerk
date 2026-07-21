require "test_helper"

class AgentEventTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @human = User.create!(name: "Human", email: "human@example.com", password: "password1")
    @hermes = User.create!(name: "Hermes", kind: :agent)
    @build_agent = User.create!(name: "Build Agent", kind: :agent)
  end

  test "message creates one mentioned event per mentioned agent after matching case insensitively" do
    assert_enqueued_jobs 2, only: DeliverAgentEventJob do
      message = Message.create!(author: @human, body: "@HERMES please ask @build-agent and @hermes again")
      assert_equal [ @hermes, @build_agent ].sort_by(&:id), message.agent_events.map(&:recipient).sort_by(&:id)
    end
  end

  test "mention requires a complete handle boundary" do
    message = Message.create!(author: @human, body: "@hermes2 and x@hermes but not the agent")

    assert_empty message.agent_events
  end

  test "human names do not create mentioned events" do
    message = Message.create!(author: @human, body: "@human hello")

    assert_empty message.agent_events
  end

  test "event uniqueness prevents duplicate recipient and message events" do
    message = Message.create!(author: @human, body: "@hermes")
    duplicate = AgentEvent.new(event_type: "mentioned", recipient: @hermes, subject: message)

    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "payload contains identifiers but no conversation content" do
    message = Message.create!(author: @human, body: "private conversation text @hermes")
    event = message.agent_events.sole
    payload = event.payload

    assert_equal event.public_id, payload[:id]
    assert_equal "mentioned", payload[:type]
    assert_equal({ id: @hermes.id, handle: "hermes" }, payload[:recipient])
    assert_equal({ type: "message", id: message.id }, payload[:subject])
    assert_equal({ conversation: "shared" }, payload[:context])
    assert_equal event.created_at.iso8601, payload[:occurred_at]
    assert_not_includes payload.to_json, message.body
  end
end
