class TaskComment < ApplicationRecord
  belongs_to :task, touch: true
  belongs_to :author, class_name: "User"
  belongs_to :agent_event, optional: true
  has_many :agent_events, as: :subject, dependent: :destroy
  has_many :activities, as: :subject
  has_many :reactions, as: :reactable, dependent: :destroy
  has_rich_text :body

  validates :body, presence: true
  validate :agent_event_matches_comment
  after_create_commit :create_mention_events
  after_create_commit :record_activity

  scope :chronologically, -> { order(:created_at, :id) }

  private

  def agent_event_matches_comment
    return unless agent_event

    source_task = case agent_event.event_type
    when "task_assigned"
      agent_event.subject.task if agent_event.subject_type == "TaskAssignment"
    when "task_comment_mentioned"
      agent_event.subject.task if agent_event.subject_type == "TaskComment"
    end
    return if source_task == task && agent_event.recipient == author

    errors.add(:agent_event, "must be the author's event for this task")
  end

  def create_mention_events
    return unless author.human?

    text = body.to_plain_text
    User.agent.find_each do |agent|
      escaped_handle = Regexp.escape(agent.handle)
      next unless text.match?(/(?<![[:alnum:]_-])@#{escaped_handle}(?![[:alnum:]_-])/i)

      agent_events.create!(event_type: "task_comment_mentioned", recipient: agent)
    end
  end

  def record_activity
    Activity.record!(trackable: task, subject: self, actor: author, activity_type: "task_comment_created")
  end
end
