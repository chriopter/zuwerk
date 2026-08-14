class ChatMessage < ApplicationRecord
  MAX_BODY_LENGTH = 50_000
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

  # The project home renders its own markup for the same record, so it needs a
  # dom id that cannot collide with the chat bubble's.
  def live_dom_id = ActionView::RecordIdentifier.dom_id(self, :live)

  private
    # The column is NOT NULL, so an attachment-only message stores an empty body.
    def normalize_body
      self.body = body.to_s
    end

    def body_or_attachment_present
      errors.add(:body, :blank) if body.blank? && !attachments.attached?
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

    # Both surfaces render for nobody in particular — a broadcast is one render
    # shared by every subscriber — so "is-own" is applied per viewer in the
    # browser from the author id on the element.
    def broadcast_append
      broadcast_append_to chat.message_stream, target: "messages", partial: "chat_messages/chat_message", locals: { current_user: nil }
      broadcast_append_to chat.home_stream, target: "project_live_messages", partial: "projects/live_message", locals: { current_user: nil }
    end

    def broadcast_replace
      broadcast_replace_to chat.message_stream, partial: "chat_messages/chat_message", locals: { current_user: nil }
      broadcast_replace_to chat.home_stream, target: live_dom_id, partial: "projects/live_message", locals: { current_user: nil }
    end

    def broadcast_remove
      broadcast_remove_to chat.message_stream
      # Addressed through the channel because the record helper removes its own
      # dom id, and the project home renders this message under a different one.
      Turbo::StreamsChannel.broadcast_remove_to chat.home_stream, target: live_dom_id
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
