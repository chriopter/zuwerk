module HostedAgents
  class StartupReconciler
    STARTABLE_STATES = %w[provisioning starting running].freeze

    def self.call(scope: HostedAgent.where(state: STARTABLE_STATES), runtime_factory: ->(hosted_agent) { ContainerRuntime.new(hosted_agent) })
      scope.find_each do |hosted_agent|
        runtime = runtime_factory.call(hosted_agent)
        runtime.provision unless runtime.running?
      rescue StandardError => error
        Rails.logger.error("Hosted agent #{hosted_agent.id} startup reconciliation failed: #{error.class}: #{error.message}")
      end
    end
  end
end
