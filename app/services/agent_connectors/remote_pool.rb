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
            on_permission: ->(request_id, params) { await_approval(event, request_id, params, client: entry[:client], expected_connector_owner: expected_connector_owner) },
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

        def await_approval(event, request_id, params, client:, expected_connector_owner: event.connector_connection_id)
          options = Array(params["options"] || params[:options])
          details = params.except("options", :options)
          approval = event.with_lock do
            event.reload
            next unless event.state == "running" && event.connector_connection_id == expected_connector_owner
            event.agent_approvals.create!(request_id: request_id, options: options, details: details)
          end
          return HostedAgents::AcpClient::PERMISSION_CANCELLED unless approval
          ActiveRecord::Base.connection_handler.clear_active_connections!
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 300
          while client.alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            pending = approval.reload.pending?
            ActiveRecord::Base.connection_handler.clear_active_connections!
            break unless pending

            AgentApprovals::Waiters.wait(approval.id, timeout: 0.25)
          end
          outcome = approval.with_lock do
            approval.reload
            event.with_lock do
              event.reload
              if event.connector_connection_id != expected_connector_owner
                if approval.pending?
                  approval.update!(state: "cancelled", cancelled_at: Time.current)
                  event.update!(state: "running", waiting_at: nil) if event.state == "waiting_for_approval"
                end
                [ :cancelled ]
              elsif approval.state == "resolved"
                [ :selected, approval.selected_option_id ]
              elsif approval.pending?
                if client.alive?
                  approval.update!(state: "expired", expired_at: Time.current)
                else
                  approval.update!(state: "cancelled", cancelled_at: Time.current)
                end
                event.update!(state: "cancelled", finished_at: Time.current) if event.state.in?(%w[running waiting_for_approval queued])
                [ :cancelled ]
              else
                [ :cancelled ]
              end
            end
          end
          AgentApprovals::Waiters.signal(approval.id)
          return outcome.last if outcome.first == :selected

          HostedAgents::AcpClient::PERMISSION_CANCELLED
        end
    end
  end
end
