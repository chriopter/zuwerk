class AgentSubscription < ApplicationRecord
  belongs_to :project
  belongs_to :agent, class_name: "User"

  validates :agent_id, uniqueness: { scope: :project_id }
  validate :agent_identity

  private
    def agent_identity
      errors.add(:agent, "must be an agent") unless agent&.agent?
    end
end
