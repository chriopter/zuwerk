class TaskAssignment < ApplicationRecord
  belongs_to :task
  belongs_to :agent, class_name: "User"
  belongs_to :assigned_by, class_name: "User"
  has_many :agent_events, as: :subject, dependent: :destroy

  validates :agent_id, uniqueness: { scope: :task_id }
  validate :agent_identity

  after_create_commit :wake_agent

  delegate :project, to: :task

  private

  def agent_identity
    errors.add(:agent, "must be an agent") unless agent&.agent?
  end

  def wake_agent
    agent_events.create!(recipient: agent, event_type: "task_assigned")
  end
end
