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
