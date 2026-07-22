class AgentApprovalsController < ApplicationController
  before_action :require_human!

  def update
    approval = AgentApproval.find(params[:id])
    approval.resolve!(selected_option_id(approval), resolver: current_user)
    if request.format.json? || params.key?(:option_id)
      head :no_content
    else
      redirect_to origin_path(approval), status: :see_other
    end
  rescue AgentApproval::ResolutionError => error
    render plain: error.message, status: :conflict
  rescue IndexError, ArgumentError
    render plain: "Option is not valid for this request", status: :unprocessable_entity
  end

  private
    def selected_option_id(approval)
      return approval.options.fetch(Integer(params.require(:option_index))).fetch("optionId") if params.key?(:option_index)

      raise ActionController::ParameterMissing, :option_id unless params.key?(:option_id)
      value = params[:option_id]
      value.is_a?(ActionController::Parameters) ? value.to_unsafe_h : value
    end

    def origin_path(approval)
      event = approval.agent_event
      event.todo ? project_todo_path(event.project, event.todo) : chat_project_path(event.project)
    end
end
