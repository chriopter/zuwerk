class Reaction < ApplicationRecord
  EMOJIS = %w[👍 ❤️ 🎉 😂 😮 😢 🙏 🚀 👀 ✅].freeze
  REACTABLE_TYPES = %w[ChatMessage Task TaskComment].freeze

  belongs_to :author, class_name: "User"
  belongs_to :reactable, polymorphic: true

  validates :emoji, inclusion: { in: EMOJIS }, uniqueness: { scope: %i[author_id reactable_type reactable_id] }
  validates :reactable_type, inclusion: { in: REACTABLE_TYPES }

  after_commit :refresh_reactable

  private
    def refresh_reactable
      case reactable_type
      when "ChatMessage"
        reactable.reload.broadcast_replace_to reactable.project.chat_message_stream,
          target: ActionView::RecordIdentifier.dom_id(reactable), partial: "chat_messages/chat_message",
          locals: { chat_message: reactable, current_user: nil }
      when "Task"
        reactable.reload.broadcast_replace_to "task_#{reactable.id}_status",
          target: "task_reactions", partial: "reactions/reaction_frame",
          locals: { task: reactable }
      end
    end
end
