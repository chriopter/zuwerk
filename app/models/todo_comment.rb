class TodoComment < ApplicationRecord
  belongs_to :todo, touch: true
  belongs_to :author, class_name: "User"
  belongs_to :agent_event, optional: true
  has_many :agent_events, as: :subject, dependent: :destroy
  has_many :reactions, as: :reactable, dependent: :destroy
  has_rich_text :body

  validates :body, presence: true
  validate :agent_event_matches_comment
  after_create_commit :create_mention_events

  scope :chronologically, -> { order(:created_at, :id) }

  private

  def agent_event_matches_comment
    return unless agent_event

    source_todo = case agent_event.event_type
    when "todo_assigned"
      agent_event.subject.todo if agent_event.subject_type == "TodoAssignment"
    when "comment_mentioned"
      agent_event.subject.todo if agent_event.subject_type == "TodoComment"
    end
    return if source_todo == todo && agent_event.recipient == author

    errors.add(:agent_event, "must be the author's event for this todo")
  end

  def create_mention_events
    return unless author.human?

    text = body.to_plain_text
    User.agent.find_each do |agent|
      escaped_handle = Regexp.escape(agent.handle)
      next unless text.match?(/(?<![[:alnum:]_-])@#{escaped_handle}(?![[:alnum:]_-])/i)

      agent_events.create!(event_type: "comment_mentioned", recipient: agent)
    end
  end
end
