class RoomSetting < ApplicationRecord
  validates :room_key, presence: true, uniqueness: true

  def self.current
    find_or_create_by!(room_key: "shared")
  end
end
