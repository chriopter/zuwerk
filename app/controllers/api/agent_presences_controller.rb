module Api
  class AgentPresencesController < BaseController
    def update
      if params[:status] == "working"
        @current_agent.update(working_status: true, working_label: params[:label].presence, heartbeat_at: Time.current)
      elsif params[:status] == "idle"
        @current_agent.update(working_status: false, working_label: nil, heartbeat_at: nil)
      else
        @current_agent.errors.add(:working_status, "must be working or idle")
      end

      if @current_agent.errors.empty?
        render json: { status: @current_agent.working? ? "working" : "idle", label: @current_agent.working_label }
      else
        render json: { errors: @current_agent.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end
end
