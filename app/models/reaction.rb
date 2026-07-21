class Reaction < ApplicationRecord
  EMOJIS = %w[👍 ❤️ 🎉].freeze
  belongs_to :user
  belongs_to :message
  validates :emoji, inclusion: { in: EMOJIS }, uniqueness: { scope: %i[user_id message_id] }
  after_commit :refresh_message

  private
    def refresh_message
      message.reload
      broadcast_replace_to "messages", target: ActionView::RecordIdentifier.dom_id(message), partial: "messages/message", locals: { message: message, current_user: nil }
    end
end
