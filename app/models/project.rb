class Project < ApplicationRecord
  has_many :search_documents, dependent: :destroy
  has_many :messages, dependent: :destroy
  has_many :agent_subscriptions, dependent: :destroy
  has_many :automatically_notified_agents, through: :agent_subscriptions, source: :agent
  has_many :todos, dependent: :destroy
  has_many :board_automations, dependent: :destroy
  has_many :board_posts, through: :board_automations
  has_many :file_entries, class_name: "ProjectFileEntry", dependent: :destroy
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

  def agent_turn_stream
    "project_#{id}_agent_turns"
  end
end
