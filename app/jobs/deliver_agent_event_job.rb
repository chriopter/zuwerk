class DeliverAgentEventJob < ApplicationJob
  class_attribute :fallback_delivery_factory, default: ->(event, url:, secret:) { AgentEventDelivery.new(event, url: url, secret: secret) }
  queue_as :default

  retry_on AgentEventDelivery::DeliveryError, wait: :polynomially_longer, attempts: 10 do |job, error|
    job.arguments.first.terminalize_failure!(error)
  end
  def perform(agent_event)
    return if agent_event.event_type == "board_scheduled"

    claimed = AgentEvent.claim_for_fallback!(agent_event)
    return unless claimed == agent_event

    fallback_delivery_factory.call(
      agent_event,
      url: ENV["ZUWERK_WEBHOOK_URL"],
      secret: ENV["ZUWERK_WEBHOOK_SECRET"]
    ).deliver
  end
end
