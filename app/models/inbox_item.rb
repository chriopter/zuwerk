class InboxItem < ApplicationRecord
  belongs_to :project
  belongs_to :user
  belongs_to :trackable, polymorphic: true
  belongs_to :latest_activity, class_name: "Activity"

  validates :user_id, uniqueness: { scope: %i[trackable_type trackable_id] }
  validate :relationships_match

  scope :recent_first, -> { order(updated_at: :desc, id: :desc) }
  scope :unread, -> { where(read_at: nil) }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end

  private

  def relationships_match
    return unless project && trackable && latest_activity

    errors.add(:project, "must match the trackable project") unless trackable.project == project
    errors.add(:latest_activity, "must belong to the trackable") unless latest_activity.trackable == trackable
  end
end
