class WarmHostedAgentBridgesJob < ApplicationJob
  queue_as :hosted_agents

  def perform
    running = HostedAgent.where(state: "running")
    HostedAgents::AcpPool.reconcile(running.ids)

    running.find_each do |hosted_agent|
      provisioner = HostedAgents::CliProvisioner.new(hosted_agent)
      provisioner.call
      provisioner.verify!
      HostedAgents::AcpPool.warm(hosted_agent)
    rescue StandardError => error
      hosted_agent.update_columns(bridge_connected_at: nil, bridge_last_error: error.message.to_s.truncate(500), updated_at: Time.current)
      Rails.logger.error("Hosted agent #{hosted_agent.id} bridge warmup failed: #{error.message}")
    end
  end
end
