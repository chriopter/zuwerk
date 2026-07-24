module Api
  class ChatMessagesController < BaseController
    def index
      messages = project.chat.messages.includes(:author, attachments_attachments: :blob).order(:created_at).last(200)
      render json: messages.map { |message| serialize(message) }
    end

    def create
      return create_for_event if params[:event_id].present?

      save_message(@current_agent.chat_messages.new(body: params[:body], attachments: params[:attachments], chat: project.chat))
    end

    def attachment
      message = project.chat.messages.find(params[:message_id])
      attachment = message.attachments.find(params[:id])
      send_data attachment.download,
        filename: attachment.filename.to_s,
        type: attachment.content_type,
        disposition: :attachment
    end

    def self.serialize(message)
      {
        id: message.id,
        body: message.body,
        created_at: message.created_at.iso8601,
        project: { id: message.project.id, name: message.project.name },
        user: { id: message.author.id, name: message.author.name, kind: message.author.kind },
        attachments: message.attachments.map do |attachment|
          {
            id: attachment.id,
            filename: attachment.filename.to_s,
            content_type: attachment.content_type,
            byte_size: attachment.byte_size,
            download_path: "/api/projects/#{message.project.id}/chat/messages/#{message.id}/attachments/#{attachment.id}"
          }
        end
      }
    end

    private
      def serialize(message)
        self.class.serialize(message)
      end

      def project
        @project ||= Project.find(params[:project_id])
      end

      def create_for_event
        event = @current_agent.agent_events.find_by!(public_id: params[:event_id])
        unless event.event_type == "chat_message_mentioned" && event.subject_type == "ChatMessage" && event.subject.project == project
          raise ActiveRecord::RecordNotFound.new("AgentEvent not found", "AgentEvent")
        end

        event.with_lock do
          if event.publication_chat_message
            render json: serialize(event.publication_chat_message), status: :ok
          else
            save_message(@current_agent.chat_messages.new(body: params[:body], attachments: params[:attachments], chat: project.chat, agent_event: event))
          end
        end
      end

      def save_message(message)
        if message.save
          render json: serialize(message), status: :created
        else
          render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end
  end
end
