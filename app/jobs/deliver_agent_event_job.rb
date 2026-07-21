class DeliverAgentEventJob < ApplicationJob
  retry_on AgentEventDelivery::DeliveryError, wait: :polynomially_longer, attempts: 10

  def perform(agent_event)
    AgentEventDelivery.new(
      agent_event,
      url: ENV["ZUWERK_WEBHOOK_URL"],
      secret: ENV["ZUWERK_WEBHOOK_SECRET"]
    ).deliver
  end
end
