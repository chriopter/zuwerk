class AgentSubscriptionsController < ApplicationController
  before_action :require_human!

  def update
    project = Project.find(params[:project_id])
    agent = User.agent.find(params[:id])

    if ActiveModel::Type::Boolean.new.cast(params[:enabled])
      project.agent_subscriptions.find_or_create_by!(agent: agent)
      notice = "#{agent.name} will now answer on every message."
    else
      project.agent_subscriptions.where(agent: agent).destroy_all
      notice = "#{agent.name} will only answer when tagged."
    end

    redirect_to chat_project_path(project), notice: notice
  end
end
