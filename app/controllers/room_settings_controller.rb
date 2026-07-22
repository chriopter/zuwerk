class RoomSettingsController < ApplicationController
  before_action :require_human!

  def update
    project = params[:project_id].present? ? Project.find(params[:project_id]) : Project.default
    project.room_setting.update!(notify_agents: ActiveModel::Type::Boolean.new.cast(params.dig(:room_setting, :notify_agents)))
    redirect_to chat_project_path(project), notice: "Agent notifications updated."
  end
end
