module AgentConnectors
  class Dispatcher
    def initialize(event, connection_id:, pool: RemotePool)
      @event = event
      @connection_id = connection_id
      @pool = pool
    end

    def deliver
      HostedAgents::ChatBridge.new(@event, pool: @pool, connector: true, expected_connector_owner: @connection_id).deliver
    end
  end
end
