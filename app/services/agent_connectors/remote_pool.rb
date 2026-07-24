module AgentConnectors
  class RemotePool
    class << self
      attr_writer :client_factory

      def prompt(agent, origin, text, event:, expected_connector_owner:, &on_chunk)
        transport = AgentConnectors.registry.fetch(agent.id)
        raise ChatBridge::DeliveryError, "ACP connector is not connected" unless transport

        mutex_for(agent.id).synchronize do
          entry = entry_for(agent.id, transport)
          context = session_context(origin)
          key = [ context.class.polymorphic_name, context.id ]
          session_id = entry[:sessions][key] ||= entry[:client].new_session
          AgentSession.record_usage!(agent:, context:, external_session_id: session_id)
          sync_connector_model(agent, entry[:client])
          result = entry[:client].prompt(
            session_id,
            text,
            on_permission: ->(request_id, params) { AgentApprovals::Gate.await(event, request_id, params, client: entry[:client], expected_connector_owner: expected_connector_owner) },
            &on_chunk
          )
          sync_connector_model(agent, entry[:client])
          result
        end
      rescue
        cleanup(agent.id, transport)
        raise
      end

      private
        def maps_mutex = (@maps_mutex ||= Mutex.new)
        def entries = (@entries ||= {})
        def client_factory = (@client_factory ||= ->(transport) { AcpClient.new(transport:) })

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

        def sync_connector_model(agent, client)
          model = client.current_model_name
          return if model.blank? || agent.connector_model == model

          agent.update!(connector_model: model)
        end

        def session_context(origin)
          origin.is_a?(Project) ? origin.chat : origin
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
