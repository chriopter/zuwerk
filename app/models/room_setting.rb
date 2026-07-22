class RoomSetting < ApplicationRecord
  belongs_to :project

  validates :project_id, uniqueness: true

  def self.current(project = Project.default)
    project.room_setting
  end
end
