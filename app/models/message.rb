class Message < ApplicationRecord
  belongs_to :author, class_name: "User"
  has_many :reactions, dependent: :destroy
  has_many :agent_events, as: :subject, dependent: :destroy
  validates :body, presence: true, length: { maximum: 4_000 }
  after_create :create_mention_events
  after_create_commit -> { broadcast_append_to "messages", target: "messages", partial: "messages/message", locals: { current_user: nil } }

  private
    def create_mention_events
      User.agent.find_each do |agent|
        escaped_handle = Regexp.escape(agent.handle)
        next unless body.match?(/(?<![[:alnum:]_-])@#{escaped_handle}(?![[:alnum:]_-])/i)

        agent_events.create!(event_type: "mentioned", recipient: agent)
      end
    end
end
