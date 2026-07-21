class RoomSettingsController < ApplicationController
  def update
    RoomSetting.current.update!(notify_agents: ActiveModel::Type::Boolean.new.cast(params.dig(:room_setting, :notify_agents)))
    redirect_to root_path, notice: "Agent notifications updated."
  end
end
