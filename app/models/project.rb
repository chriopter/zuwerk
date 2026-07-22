class Project < ApplicationRecord
  has_many :messages, dependent: :destroy
  has_many :agent_subscriptions, dependent: :destroy
  has_many :automatically_notified_agents, through: :agent_subscriptions, source: :agent
  has_many :todos, dependent: :destroy
  has_many :hosted_agent_sessions, as: :origin, dependent: :destroy
  has_one :room_setting, dependent: :destroy
  after_create :create_room_setting!

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { case_sensitive: false }

  def self.default
    find_or_create_by!(name: "Zuwerk")
  end

  def room_setting
    super || with_lock { RoomSetting.find_or_create_by!(project: self) }
  end

  def message_stream
    "project_#{id}_messages"
  end
end
