module AgentConnectors
  class Registry
    def initialize
      @mutex = Mutex.new
      @transports = {}
    end

    def register(agent_id, &writer)
      transport = Transport.new(&writer)
      @mutex.synchronize { @transports[agent_id]&.disconnect; @transports[agent_id] = transport }
      transport
    end

    def fetch(agent_id)
      @mutex.synchronize do
        transport = @transports[agent_id]
        transport if transport&.alive?
      end
    end

    def unregister(agent_id, transport = nil)
      @mutex.synchronize do
        current = @transports[agent_id]
        return unless current && (!transport || current.equal?(transport))
        @transports.delete(agent_id)
        current.disconnect
      end
    end
  end
end
