class DeliverAgentEventJob < ApplicationJob
  queue_as do
    arguments.first&.recipient&.hosted_agent.present? ? :hosted_agents : :default
  end

  retry_on AgentEventDelivery::DeliveryError, wait: :polynomially_longer, attempts: 10
  retry_on HostedAgents::ChatBridge::DeliveryError, wait: :polynomially_longer, attempts: 3

  def perform(agent_event)
    if agent_event.recipient.hosted_agent
      HostedAgents::ChatBridge.new(agent_event).deliver
    else
      AgentEventDelivery.new(
        agent_event,
        url: ENV["ZUWERK_WEBHOOK_URL"],
        secret: ENV["ZUWERK_WEBHOOK_SECRET"]
      ).deliver
    end
  end
end
