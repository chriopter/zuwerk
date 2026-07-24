module AgentApprovals
  # Turns an ACP permission request into a human decision. The agent's prompt
  # blocks here until somebody resolves the approval, the request expires, or
  # the event changes hands.
  class Gate
    TIMEOUT = 300

    def self.await(event, request_id, params, client:, expected_connector_owner: event.connector_connection_id)
      options = Array(params["options"] || params[:options])
      details = params.except("options", :options)
      approval = event.with_lock do
        event.reload
        next unless event.state == "running" && event.connector_connection_id == expected_connector_owner
        event.agent_approvals.create!(request_id: request_id, options: options, details: details)
      end
      return AgentConnectors::AcpClient::PERMISSION_CANCELLED unless approval

      ActiveRecord::Base.connection_handler.clear_active_connections!
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
      while client.alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        pending = approval.reload.pending?
        ActiveRecord::Base.connection_handler.clear_active_connections!
        break unless pending

        Waiters.wait(approval.id, timeout: 0.25)
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
      Waiters.signal(approval.id)
      return outcome.last if outcome.first == :selected

      AgentConnectors::AcpClient::PERMISSION_CANCELLED
    end
  end
end
