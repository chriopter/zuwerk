class Participation < ApplicationRecord
  belongs_to :project
  belongs_to :user
  belongs_to :trackable, polymorphic: true

  validates :user_id, uniqueness: { scope: %i[trackable_type trackable_id] }
  validate :project_matches_trackable

  private

  def project_matches_trackable
    errors.add(:project, "must match the trackable project") if trackable && trackable.project != project
  end
end
