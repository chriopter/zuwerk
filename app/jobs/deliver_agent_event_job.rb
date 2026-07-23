class DeliverAgentEventJob < ApplicationJob
  class_attribute :connector_dispatcher_factory, default: ->(event) { AgentConnectors::Dispatcher.new(event) }
  class_attribute :fallback_delivery_factory, default: ->(event, url:, secret:) { AgentEventDelivery.new(event, url: url, secret: secret) }
  queue_as do
    arguments.first&.recipient&.hosted_agent.present? ? :hosted_agents : :default
  end

  retry_on AgentEventDelivery::DeliveryError, wait: :polynomially_longer, attempts: 10 do |job, error|
    job.arguments.first.terminalize_failure!(error)
  end
  retry_on HostedAgents::ChatBridge::DeliveryError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.arguments.first.terminalize_failure!(error)
  end

  def perform(agent_event)
    claimed = AgentEvent.claim_for_fallback!(agent_event)
    return unless claimed == agent_event

    if agent_event.recipient.hosted_agent
      HostedAgents::ChatBridge.new(agent_event).deliver
    elsif agent_event.event_type == "board_scheduled"
      raise HostedAgents::ChatBridge::DeliveryError, "Board automations require a hosted or connected agent"
    else
      fallback_delivery_factory.call(
        agent_event,
        url: ENV["ZUWERK_WEBHOOK_URL"],
        secret: ENV["ZUWERK_WEBHOOK_SECRET"]
      ).deliver
    end
  end
end
