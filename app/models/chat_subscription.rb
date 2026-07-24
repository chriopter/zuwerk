class ChatSubscription < ApplicationRecord
  belongs_to :chat
  belongs_to :agent, class_name: "User"

  validates :agent_id, uniqueness: { scope: :chat_id }
  validate :agent_identity

  private
    def agent_identity
      errors.add(:agent, "must be an agent") unless agent&.agent?
    end
end
