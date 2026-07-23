module HostedAgents
  class StartupReconciler
    STARTABLE_STATES = %w[provisioning starting running].freeze

    def self.call(
      scope: HostedAgent.where(state: STARTABLE_STATES),
      runtime_factory: ->(hosted_agent) { ContainerRuntime.new(hosted_agent) },
      provisioner_factory: ->(hosted_agent) { CliProvisioner.new(hosted_agent) }
    )
      scope.find_each do |hosted_agent|
        runtime = runtime_factory.call(hosted_agent)
        if !runtime.running?
          runtime.provision
        elsif !runtime.container_current?
          Rails.logger.info("Hosted agent #{hosted_agent.id} is recreated to match its current container spec")
          runtime.recreate
        end
        provisioner_factory.call(hosted_agent).call
      rescue StandardError => error
        Rails.logger.error("Hosted agent #{hosted_agent.id} startup reconciliation failed: #{error.class}: #{error.message}")
      end
    end
  end
end
