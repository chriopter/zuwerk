class WatchStaleAgentEventsJob < ApplicationJob
  queue_as :default

  def perform
    AgentEvent.where(delivered_at: nil).joins(recipient: :hosted_agent).find_each do |event|
      HostedAgents::EventWatchdog.new(event).call
    rescue StandardError => error
      Rails.logger.error("Agent event #{event.id} watchdog failed: #{error.class}: #{error.message}")
    end
  end
end
