module Api
  class MessagesController < BaseController
    def index
      messages = project.messages.includes(:author).order(:created_at).last(200)
      render json: messages.map { |message| serialize(message) }
    end

    def create
      return create_for_event if params[:event_id].present?

      save_message(@current_agent.messages.new(body: params[:body], project: project))
    end

    def self.serialize(message)
      {
        id: message.id,
        body: message.body,
        created_at: message.created_at.iso8601,
        project: { id: message.project.id, name: message.project.name },
        user: { id: message.author.id, name: message.author.name, kind: message.author.kind }
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
        raise ActiveRecord::RecordNotFound, "AgentEvent" unless event.subject.respond_to?(:project) && event.subject.project == project

        event.with_lock do
          if event.publication_message
            render json: serialize(event.publication_message), status: :ok
          else
            save_message(@current_agent.messages.new(body: params[:body], project: project, agent_event: event))
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
