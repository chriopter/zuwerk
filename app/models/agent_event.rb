class AgentEvent < ApplicationRecord
  belongs_to :recipient, class_name: "User"
  belongs_to :subject, polymorphic: true
  has_one :publication_message, class_name: "Message", dependent: :nullify
  has_one :publication_comment, class_name: "TodoComment", dependent: :nullify

  before_validation :assign_public_id, on: :create
  after_create_commit -> { DeliverAgentEventJob.perform_later(self) }

  attr_readonly :public_id

  validates :public_id, presence: true, uniqueness: true
  validates :event_type, inclusion: { in: %w[mentioned todo_assigned] }
  validates :recipient_id, uniqueness: { scope: [ :event_type, :subject_type, :subject_id ] }

  scope :accepted, -> { where.not(accepted_at: nil) }

  def active?
    accepted_at? && !delivered_at? && last_error.blank?
  end

  def failed?
    accepted_at? && !delivered_at? && last_error.present?
  end

  def todo
    subject.todo if event_type == "todo_assigned"
  end

  def acknowledge!
    transaction do
      update!(accepted_at: Time.current, last_error: nil)
      acknowledgement_target.reactions.find_or_create_by!(author: recipient, emoji: "👍")
    end
    broadcast_work_context
  end

  def broadcast_work_context
    broadcast_replace_to "agent_work", target: "sidebar_agent_list", partial: "shared/sidebar_agent_list",
      locals: { agents: User.agent.includes(:hosted_agent).order(:name), active_agent_id: nil }
  end

  def payload
    {
      id: public_id,
      type: event_type,
      occurred_at: created_at.iso8601,
      recipient: { id: recipient.id, handle: recipient.handle },
      subject: { type: subject_type.underscore, id: subject_id },
      context: event_context
    }
  end

  private
    def acknowledgement_target
      event_type == "todo_assigned" ? todo : subject
    end

    def event_context
      context = { project: { id: subject.project.id, name: subject.project.name } }
      if event_type == "todo_assigned"
        todo = subject.todo
        context.merge(todo: { id: todo.id, title: todo.title }, origin: "todo")
      else
        context.merge(conversation: "chat")
      end
    end

    def assign_public_id
      self.public_id ||= SecureRandom.uuid
    end
end
