class ChatMessage < ApplicationRecord
  MAX_BODY_LENGTH = 4_000
  MAX_ATTACHMENTS = 5
  MAX_ATTACHMENT_SIZE = 10.megabytes

  belongs_to :chat
  belongs_to :author, class_name: "User"
  belongs_to :agent_event, optional: true
  has_many_attached :attachments
  has_many :reactions, as: :reactable, dependent: :destroy
  has_many :agent_events, as: :subject, dependent: :destroy
  has_many :activities, as: :subject
  delegate :project, to: :chat

  before_validation :normalize_body

  validates :body, length: { maximum: MAX_BODY_LENGTH }
  validate :body_or_attachment_present
  validate :acceptable_attachments
  validate :agent_event_matches_message
  after_create :create_mention_events
  after_create_commit :broadcast_append
  after_create_commit :record_activity
  after_update_commit :broadcast_replace
  after_destroy_commit :broadcast_remove

  # Images are shown inline in the feed; everything else is listed as a file.
  def image_attachments = attachments.select { |attachment| attachment.image? }
  def file_attachments = attachments.reject { |attachment| attachment.image? }

  private
    # The column is NOT NULL, so an attachment-only message stores an empty body.
    def normalize_body
      self.body = body.to_s
    end

    def body_or_attachment_present
      errors.add(:body, "can't be blank without an attachment") if body.blank? && !attachments.attached?
    end

    def acceptable_attachments
      errors.add(:attachments, "are limited to #{MAX_ATTACHMENTS} files") if attachments.size > MAX_ATTACHMENTS
      attachments.each do |attachment|
        errors.add(:attachments, "must be 10 MB or smaller") if attachment.blob.byte_size > MAX_ATTACHMENT_SIZE
      end
    end

    def agent_event_matches_message
      return unless agent_event

      source = agent_event.subject if agent_event.event_type == "chat_message_mentioned" && agent_event.subject_type == "ChatMessage"
      return if source&.project == project && agent_event.recipient == author

      errors.add(:agent_event, "must be the author's mention event for this project")
    end

    def broadcast_append
      broadcast_append_to chat.message_stream, target: "messages", partial: "chat_messages/chat_message", locals: { current_user: nil }
    end

    def broadcast_replace
      broadcast_replace_to chat.message_stream, partial: "chat_messages/chat_message", locals: { current_user: nil }
    end

    def broadcast_remove
      broadcast_remove_to chat.message_stream
    end


    def create_mention_events
      return unless author.human?

      automatically_notified_ids = chat.subscriptions.pluck(:agent_id)
      project.account.agents.find_each do |agent|
        escaped_handle = Regexp.escape(agent.handle)
        chat_message_mentioned = body.match?(/(?<![[:alnum:]_-])@#{escaped_handle}(?![[:alnum:]_-])/i)
        next unless chat_message_mentioned || automatically_notified_ids.include?(agent.id)

        agent_events.create!(event_type: "chat_message_mentioned", recipient: agent)
      end
    end

    def record_activity
      Activity.record!(trackable: chat, subject: self, actor: author, activity_type: "chat_message_created")
    end
end
