module Api
  class MessagesController < BaseController
    def index
      messages = Message.includes(:author).order(:created_at).last(200)
      render json: messages.map { |message| serialize(message) }
    end

    def create
      message = @current_agent.messages.new(body: params[:body])
      if message.save
        render json: serialize(message), status: :created
      else
        render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private
      def serialize(message)
        { id: message.id, body: message.body, created_at: message.created_at.iso8601, user: { id: message.author.id, name: message.author.name, kind: message.author.kind } }
      end
  end
end
