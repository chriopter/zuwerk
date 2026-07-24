class AgentTurnsController < ApplicationController
  before_action :require_human!

  def destroy
    project = Project.find(params[:project_id])
    agent = User.agent.find(params[:id])
    active = AgentEvent.where(recipient: agent, state: %w[queued running waiting_for_approval])
      .order(created_at: :desc).select { |event| event.project == project }
    active.each { |event| event.transition_to!("cancelled") }

    notice = active.any? ? "#{agent.name}: Turn abgebrochen." : "#{agent.name} hat keinen laufenden Turn."
    redirect_to project_chat_path(project), notice: notice
  end
end
