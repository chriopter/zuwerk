class BriefingComment < ApplicationRecord
  belongs_to :briefing
  belongs_to :author, class_name: "User"
  belongs_to :agent_event, optional: true
  has_many :agent_events, as: :subject, dependent: :destroy
  has_many :activities, as: :subject
  has_many :reactions, as: :reactable, dependent: :destroy
  has_rich_text :body

  delegate :project, to: :briefing

  validates :prompt_snapshot, presence: true, if: :scheduled?
  validates :body, presence: true, if: :published_at?
  validate :scheduled_author
  validate :publication_event_matches

  scope :published, -> { where.not(published_at: nil) }
  scope :chronologically, -> { order(:published_at, :id) }

  after_commit :update_briefing_activity

  def publish!(markdown, event:)
    html = Commonmarker.to_html(markdown.to_s, options: { render: { unsafe: false } })
    update!(body: html, published_at: Time.current, agent_event: event)
  end

  def scheduled?
    scheduled_for.present?
  end

  private

  def scheduled_author
    return unless scheduled?

    expected_agent = agent_event&.recipient || briefing.agent
    errors.add(:author, "must be the selected occurrence agent") unless author == expected_agent
  end

  def publication_event_matches
    return unless agent_event
    return if agent_event.event_type == "briefing_scheduled" && agent_event.subject == self && agent_event.recipient == author

    errors.add(:agent_event, "must be this comment's scheduled agent event")
  end

  def update_briefing_activity
    briefing = Briefing.find_by(id: briefing_id)
    return unless briefing

    published_change = previous_changes["published_at"]
    if published_change && published_change.first.nil? && published_change.last.present?
      Activity.record!(trackable: briefing, subject: self, actor: author, activity_type: "briefing_comment_created")
    end
  end
end
