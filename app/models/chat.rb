class Chat < ApplicationRecord
  include ActivityTrackable

  belongs_to :project
  has_many :messages, class_name: "ChatMessage", dependent: :destroy
  has_many :subscriptions, class_name: "ChatSubscription", dependent: :destroy
  has_many :automatically_notified_agents, through: :subscriptions, source: :agent
  validates :project_id, uniqueness: true

  before_validation :set_initial_activity, on: :create

  def message_stream
    "chat_#{id}_messages"
  end

  private

  def set_initial_activity
    self.last_activity_at ||= Time.current
  end
end
