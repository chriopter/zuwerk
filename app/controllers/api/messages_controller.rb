module Api
  class MessagesController < BaseController
    def index
      messages = selected_project.messages.includes(:author).order(:created_at).last(200)
      render json: messages.map { |message| serialize(message) }
    end

    def create
      message = @current_agent.messages.new(body: params[:body], project: selected_project)
      if message.save
        render json: serialize(message), status: :created
      else
        render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def self.serialize(message)
      {
        id: message.id,
        body: message.body,
        state: message.state,
        created_at: message.created_at.iso8601,
        project: { id: message.project.id, name: message.project.name },
        user: { id: message.author.id, name: message.author.name, kind: message.author.kind }
      }
    end

    private
      def serialize(message)
        self.class.serialize(message)
      end

      def selected_project
        @selected_project ||= params[:project_id].present? ? Project.find(params[:project_id]) : Project.default
      end
  end
end
