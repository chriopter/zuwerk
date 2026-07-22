class ProvisionHostedAgentJob < ApplicationJob
  queue_as :default

  def perform(hosted_agent)
    HostedAgents::ContainerRuntime.new(hosted_agent).provision
  end
end
