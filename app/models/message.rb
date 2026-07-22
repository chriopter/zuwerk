class Message < ApplicationRecord
  belongs_to :project
  belongs_to :author, class_name: "User"
  belongs_to :agent_event, optional: true
  has_many :reactions, as: :reactable, dependent: :destroy
  has_many :agent_events, as: :subject, dependent: :destroy
  before_validation :assign_default_project, on: :create
  validates :body, presence: true
  validates :body, length: { maximum: 4_000 }
  after_create :create_mention_events
  after_create_commit :broadcast_append

  private
    def assign_default_project
      self.project ||= Project.default
    end

    def broadcast_append
      broadcast_append_to project.message_stream, target: "messages", partial: "messages/message", locals: { current_user: nil }
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
