class Reaction < ApplicationRecord
  EMOJIS = %w[👍 ❤️ 🎉].freeze
  REACTABLE_TYPES = %w[Message TodoComment].freeze

  belongs_to :author, class_name: "User"
  belongs_to :reactable, polymorphic: true

  validates :emoji, inclusion: { in: EMOJIS }, uniqueness: { scope: %i[author_id reactable_type reactable_id] }
  validates :reactable_type, inclusion: { in: REACTABLE_TYPES }

  after_commit :refresh_message, if: -> { reactable_type == "Message" }

  private
    def refresh_message
      reactable.reload
      reactable.broadcast_replace_to reactable.project.message_stream,
        target: ActionView::RecordIdentifier.dom_id(reactable),
        partial: "messages/message",
        locals: { message: reactable, current_user: nil }
    end
end
