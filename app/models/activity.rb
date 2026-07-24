class Activity < ApplicationRecord
  TYPES = %w[briefing_comment_created chat_message_created task_comment_created].freeze

  belongs_to :project
  belongs_to :actor, class_name: "User"
  belongs_to :trackable, polymorphic: true
  belongs_to :subject, polymorphic: true
  has_many :inbox_items, foreign_key: :latest_activity_id, dependent: :destroy

  validates :activity_type, inclusion: { in: TYPES }
  validates :summary, presence: true
  validate :project_matches_trackable

  def self.record!(trackable:, subject:, actor:, activity_type:)
    transaction do
      participant_ids = trackable.participations
        .joins(:user)
        .merge(User.human)
        .where.not(user_id: actor.id)
        .pluck(:user_id)

      activity = create!(
        project: trackable.project,
        actor: actor,
        trackable: trackable,
        subject: subject,
        activity_type: activity_type,
        summary: summary_for(subject)
      )
      trackable.register_participant!(actor)
      trackable.update_column(:last_activity_at, activity.created_at)

      participant_ids.each do |user_id|
        item = InboxItem.find_or_initialize_by(user_id: user_id, trackable: trackable)
        item.assign_attributes(project: trackable.project, latest_activity: activity, read_at: nil)
        item.save!
      end
      activity
    end
  end

  private

  def self.summary_for(subject)
    body = subject.body
    text = body.respond_to?(:to_plain_text) ? body.to_plain_text : body.to_s
    text.squish.truncate(500)
  end

  def project_matches_trackable
    errors.add(:project, "must match the trackable project") if trackable && trackable.project != project
  end
end
