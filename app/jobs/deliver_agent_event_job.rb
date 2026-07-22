class DeliverAgentEventJob < ApplicationJob
  class_attribute :connector_dispatcher_factory, default: ->(event) { AgentConnectors::Dispatcher.new(event) }
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
    agent_event.reload
    return unless agent_event.state.in?(%w[queued running])

    claimed = agent_event.state == "queued" ? AgentEvent.claim_next_for!(agent_event.recipient) : agent_event
    return unless claimed == agent_event

    if AgentConnectors.registry.fetch(agent_event.recipient_id)
      connector_dispatcher_factory.call(agent_event).deliver
    elsif agent_event.recipient.hosted_agent
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
