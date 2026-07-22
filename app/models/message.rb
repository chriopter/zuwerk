class Message < ApplicationRecord
  belongs_to :project
  belongs_to :author, class_name: "User"
  has_many :reactions, dependent: :destroy
  has_many :agent_events, as: :subject, dependent: :destroy
  enum :state, { completed: 0, streaming: 1 }
  before_validation :assign_default_project, on: :create
  validates :body, presence: true, if: :completed?
  validates :body, length: { maximum: 4_000 }
  after_create :create_mention_events
  after_create_commit :broadcast_append
  after_update_commit :broadcast_replace

  private
    def assign_default_project
      self.project ||= Project.default
    end

    def broadcast_append
      broadcast_append_to project.message_stream, target: "messages", partial: "messages/message", locals: { current_user: nil }
    end

    def broadcast_replace
      broadcast_replace_to project.message_stream, target: ActionView::RecordIdentifier.dom_id(self), partial: "messages/message", locals: { current_user: nil }
    end

    def create_mention_events
      return unless author.human?

      User.agent.find_each do |agent|
        escaped_handle = Regexp.escape(agent.handle)
        mentioned = body.match?(/(?<![[:alnum:]_-])@#{escaped_handle}(?![[:alnum:]_-])/i)
        next unless mentioned || project.room_setting.notify_agents?

        agent_events.create!(event_type: "mentioned", recipient: agent)
      end
    end
end
