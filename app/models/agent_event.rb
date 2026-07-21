class AgentEvent < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :subject, polymorphic: true

  before_validation :assign_public_id, on: :create
  after_create_commit -> { DeliverAgentEventJob.perform_later(self) }

  attr_readonly :public_id

  validates :public_id, presence: true, uniqueness: true
  validates :event_type, inclusion: { in: %w[mentioned] }
  validates :recipient_id, uniqueness: { scope: [ :event_type, :subject_type, :subject_id ] }

  def payload
    {
      id: public_id,
      type: event_type,
      occurred_at: created_at.iso8601,
      recipient: { id: recipient.id, handle: recipient.handle },
      subject: { type: subject_type.underscore, id: subject_id },
      context: { conversation: "shared" }
    }
  end

  private
    def assign_public_id
      self.public_id ||= SecureRandom.uuid
    end
end
