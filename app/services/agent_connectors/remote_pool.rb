module AgentConnectors
  class RemotePool
    class << self
      attr_writer :client_factory

      def prompt(agent, origin, text, event:, expected_connector_owner:, &on_chunk)
        transport = AgentConnectors.registry.fetch(agent.id)
        raise HostedAgents::ChatBridge::DeliveryError, "ACP connector is not connected" unless transport

        mutex_for(agent.id).synchronize do
          entry = entry_for(agent.id, transport)
          key = [ origin.class.polymorphic_name, origin.id ]
          session_id = entry[:sessions][key] ||= entry[:client].new_session
          entry[:client].prompt(
            session_id,
            text,
            on_permission: ->(request_id, params) { AgentApprovals::Gate.await(event, request_id, params, client: entry[:client], expected_connector_owner: expected_connector_owner) },
            &on_chunk
          )
        end
      rescue
        cleanup(agent.id, transport)
        raise
      end

      private
        def maps_mutex = (@maps_mutex ||= Mutex.new)
        def entries = (@entries ||= {})
        def client_factory = (@client_factory ||= ->(transport) { HostedAgents::AcpClient.new(nil, transport: transport) })

        def mutex_for(id)
          maps_mutex.synchronize { (@mutexes ||= {})[id] ||= Mutex.new }
        end

        def entry_for(id, transport)
          entry = maps_mutex.synchronize { entries[id] }
          return entry if entry&.fetch(:transport)&.equal?(transport) && entry.fetch(:client).alive?

          replacement = { transport: transport, client: client_factory.call(transport), sessions: {} }
          previous = maps_mutex.synchronize do
            existing = entries[id]
            entries[id] = replacement
            existing
          end
          previous&.fetch(:client)&.close
          replacement
        end

        def cleanup(id, transport)
          mutex_for(id).synchronize do
            client = maps_mutex.synchronize do
              entry = entries[id]
              entries.delete(id)&.fetch(:client) if entry&.fetch(:transport)&.equal?(transport)
            end
            client&.close
          end
        end

        def reset!
          old_entries = maps_mutex.synchronize do
            existing = entries.values
            @entries = {}
            existing
          end
          old_entries.each { |entry| entry.fetch(:client).close }
        end
    end
  end
end
