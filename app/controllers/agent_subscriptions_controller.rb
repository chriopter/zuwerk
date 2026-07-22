class AgentSubscriptionsController < ApplicationController
  before_action :require_human!

  def update
    project = Project.find(params[:project_id])
    agent = User.agent.find(params[:id])

    if ActiveModel::Type::Boolean.new.cast(params[:enabled])
      project.agent_subscriptions.find_or_create_by!(agent: agent)
    else
      project.agent_subscriptions.where(agent: agent).destroy_all
    end

    redirect_to chat_project_path(project), notice: "Automatic bot notifications updated."
  end
end
