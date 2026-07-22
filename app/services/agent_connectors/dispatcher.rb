module AgentConnectors
  class Dispatcher
    def initialize(event)
      @event = event
    end

    def deliver
      HostedAgents::ChatBridge.new(@event, pool: RemotePool, connector: true).deliver
    end
  end
end
