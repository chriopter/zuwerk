require "test_helper"

class DeliverAgentEventJobTest < ActiveJob::TestCase
  setup do
    @human = User.create!(name: "Job Human", email: "job-#{SecureRandom.hex(4)}@example.com", password: "password1")
    @agent = User.create!(name: "Job Agent #{SecureRandom.hex(2)}", kind: :agent)
    @project = Project.create!(name: "Job Project")
  end

  teardown do
    DeliverAgentEventJob.fallback_delivery_factory = ->(event, url:, secret:) { AgentEventDelivery.new(event, url:, secret:) }
  end

  test "delivers an unclaimed mention through the webhook fallback" do
    event = mention_event
    delivered = []
    DeliverAgentEventJob.fallback_delivery_factory = lambda do |candidate, **|
      Struct.new(:candidate, :delivered) { def deliver = delivered << candidate }.new(candidate, delivered)
    end

    DeliverAgentEventJob.perform_now(event)

    assert_equal [ event ], delivered
    assert_equal "running", event.reload.state
    assert_nil event.connector_connection_id
  end

  test "does not steal work from a connected ACP agent" do
    event = mention_event
    @agent.update_columns(connector_connection_id: "connector", connector_heartbeat_at: Time.current)
    DeliverAgentEventJob.fallback_delivery_factory = ->(*) { raise "must not deliver" }

    DeliverAgentEventJob.perform_now(event)

    assert_equal "queued", event.reload.state
  end

  test "does not redispatch terminal events" do
    event = mention_event
    DeliverAgentEventJob.fallback_delivery_factory = ->(*) { raise "must not deliver" }

    %w[completed failed cancelled].each do |state|
      event.update_columns(state:, finished_at: Time.current)
      DeliverAgentEventJob.perform_now(event)
      assert_equal state, event.reload.state
    end
  end

  test "board work waits for an ACP connector" do
    automation = BoardAutomation.create!(
      project: @project,
      creator: @human,
      agent: @agent,
      title: "Report",
      cadence: "daily",
      prompt: "Publish"
    )
    event = automation.run_now!.agent_event
    DeliverAgentEventJob.fallback_delivery_factory = ->(*) { raise "must not deliver" }

    DeliverAgentEventJob.perform_now(event)

    assert_equal "queued", event.reload.state
    assert_nil event.accepted_at
  end

  private
    def mention_event
      message = Message.create!(author: @human, project: @project, body: "Please work")
      AgentEvent.create!(recipient: @agent, subject: message, event_type: "mentioned")
    end
end
