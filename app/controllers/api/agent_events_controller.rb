module Api
  class AgentEventsController < BaseController
    def acknowledge
      event = @current_agent.agent_events.find_by!(public_id: params[:id])
      raise ActiveRecord::RecordNotFound.new("AgentEvent not found", "AgentEvent") unless event.state.in?(%w[running waiting_for_approval completed])

      event.acknowledge!
      render json: {
        id: event.public_id,
        state: event.state,
        acknowledged_at: event.accepted_at.iso8601
      }
    end
  end
end
