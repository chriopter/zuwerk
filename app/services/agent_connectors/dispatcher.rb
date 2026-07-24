module AgentConnectors
  class Dispatcher
    def initialize(event, connection_id:, pool: RemotePool)
      @event = event
      @connection_id = connection_id
      @pool = pool
    end

    def deliver
      ChatBridge.new(@event, connection_id: @connection_id, pool: @pool).deliver
    end
  end
end
