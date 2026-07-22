class TodoAssignment < ApplicationRecord
  belongs_to :todo
  belongs_to :agent, class_name: "User"
  belongs_to :assigner, class_name: "User"
  has_many :agent_events, as: :subject, dependent: :destroy

  validates :agent_id, uniqueness: { scope: :todo_id }
  validate :agent_identity

  after_create_commit :wake_agent

  delegate :project, to: :todo

  private

  def agent_identity
    errors.add(:agent, "must be an agent") unless agent&.agent?
  end

  def wake_agent
    agent_events.create!(recipient: agent, event_type: "todo_assigned")
  end
end
