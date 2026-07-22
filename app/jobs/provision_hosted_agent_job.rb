class ProvisionHostedAgentJob < ApplicationJob
  queue_as :default

  def perform(hosted_agent)
    HostedAgents::ContainerRuntime.new(hosted_agent).provision
    HostedAgents::CliProvisioner.new(hosted_agent).call
  end
end
