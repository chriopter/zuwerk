class WarmHostedAgentBridgesJob < ApplicationJob
  queue_as :hosted_agents

  def perform
    running = HostedAgent.where(state: "running")
    HostedAgents::AcpPool.reconcile(running.ids)

    running.find_each do |hosted_agent|
      HostedAgents::AcpPool.warm(hosted_agent)
    rescue HostedAgents::AcpClient::Error => error
      Rails.logger.error("Hosted agent #{hosted_agent.id} bridge warmup failed: #{error.message}")
    end
  end
end
