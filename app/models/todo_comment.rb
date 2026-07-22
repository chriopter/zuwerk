class TodoComment < ApplicationRecord
  belongs_to :todo, touch: true
  belongs_to :author, class_name: "User"
  belongs_to :agent_event, optional: true
  has_many :reactions, as: :reactable, dependent: :destroy
  has_rich_text :body

  validates :body, presence: true
  validate :agent_event_matches_comment

  scope :chronologically, -> { order(:created_at, :id) }

  private

  def agent_event_matches_comment
    return unless agent_event

    assignment = agent_event.subject if agent_event.event_type == "todo_assigned" && agent_event.subject_type == "TodoAssignment"
    return if assignment&.todo == todo && agent_event.recipient == author

    errors.add(:agent_event, "must be the author's assignment event for this todo")
  end
end
