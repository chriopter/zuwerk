module ActivityTrackable
  extend ActiveSupport::Concern

  included do
    has_many :activities, as: :trackable, dependent: :destroy
    has_many :participations, as: :trackable, dependent: :destroy
    has_many :inbox_items, as: :trackable, dependent: :destroy

    validates :last_activity_at, presence: true
    scope :recently_active, -> { order(last_activity_at: :desc, id: :desc) }
  end

  def register_participant!(user)
    participations.find_or_create_by!(project: project, user: user)
  end
end
