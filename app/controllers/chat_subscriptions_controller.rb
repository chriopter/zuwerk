class ChatSubscriptionsController < ApplicationController
  before_action :require_human!

  def update
    project = find_project(params[:project_id])
    agent = current_account_agents.find(params[:id])

    if ActiveModel::Type::Boolean.new.cast(params[:enabled])
      project.chat.subscriptions.find_or_create_by!(agent: agent)
      notice = "#{agent.name} will now answer on every message."
    else
      project.chat.subscriptions.where(agent: agent).destroy_all
      notice = "#{agent.name} will only answer when tagged."
    end

    redirect_to project_chat_path(project), notice: notice
  end
end
