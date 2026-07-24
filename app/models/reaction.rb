class Reaction < ApplicationRecord
  EMOJIS = %w[👍 ❤️ 🎉 😂 😮 😢 🙏 🚀 👀 ✅].freeze
  REACTABLE_TYPES = %w[Message Todo TodoComment].freeze

  belongs_to :author, class_name: "User"
  belongs_to :reactable, polymorphic: true

  validates :emoji, inclusion: { in: EMOJIS }, uniqueness: { scope: %i[author_id reactable_type reactable_id] }
  validates :reactable_type, inclusion: { in: REACTABLE_TYPES }

  after_commit :refresh_reactable

  private
    def refresh_reactable
      case reactable_type
      when "Message"
        reactable.reload.broadcast_replace_to reactable.project.message_stream,
          target: ActionView::RecordIdentifier.dom_id(reactable), partial: "messages/message",
          locals: { message: reactable, current_user: nil }
      when "Todo"
        reactable.reload.broadcast_replace_to "todo_#{reactable.id}_status",
          target: "todo_reactions", partial: "reactions/reaction_frame",
          locals: { todo: reactable }
      end
    end
end
