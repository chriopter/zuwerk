class ManageHostedAgentJob < ApplicationJob
  queue_as :default

  def perform(hosted_agent, action)
    raise ArgumentError, "Unsupported action" unless %w[start stop restart recreate].include?(action)

    HostedAgents::ContainerRuntime.new(hosted_agent).public_send(action)
  end
end
