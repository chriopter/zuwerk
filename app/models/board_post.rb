class BoardPost < ApplicationRecord
  belongs_to :board_automation
  belongs_to :author, class_name: "User"
  belongs_to :agent_event, optional: true
  has_many :agent_events, as: :subject, dependent: :destroy
  has_rich_text :body

  delegate :project, to: :board_automation

  validates :title, presence: true, length: { maximum: 160 }
  validates :scheduled_for, presence: true
  validates :prompt_snapshot, presence: true, length: { maximum: 20_000 }
  validates :body, presence: true, if: :published_at?
  validate :author_is_automation_agent
  validate :publication_event_matches

  scope :published, -> { where.not(published_at: nil).order(published_at: :desc, id: :desc) }

  def publish!(markdown, event:)
    html = Commonmarker.to_html(markdown.to_s, options: { render: { unsafe: false } })
    update!(body: html, published_at: Time.current, agent_event: event)
  end

  private

  def author_is_automation_agent
    return if board_automation.nil?

    expected_agent = agent_event&.recipient || board_automation.agent
    return if author == expected_agent

    errors.add(:author, "must be the selected occurrence agent")
  end

  def publication_event_matches
    return unless agent_event
    return if agent_event.event_type == "board_scheduled" && agent_event.subject == self && agent_event.recipient == author

    errors.add(:agent_event, "must be this post's scheduled agent event")
  end
end
