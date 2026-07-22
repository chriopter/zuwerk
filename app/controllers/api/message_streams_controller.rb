module Api
  class MessageStreamsController < BaseController
    MAX_CHUNK_SIZE = 1_000

    def create
      message = @current_agent.messages.new(body: params[:body].to_s, state: :streaming, project: selected_project)
      save_or_error(message, :created)
    end

    def update
      message = owned_stream
      return unless message
      operation = request.request_parameters["action"]
      case operation
      when "append"
        return render json: { errors: [ "Chunk is too long" ] }, status: :unprocessable_entity if params[:chunk].to_s.length > MAX_CHUNK_SIZE
        message.body += params[:chunk].to_s
      when "replace"
        message.body = params[:body].to_s
      when "finish"
        message.state = :completed
      else
        return render json: { errors: [ "Action must be append, replace, or finish" ] }, status: :unprocessable_entity
      end
      save_or_error(message)
    end

    private
      def selected_project
        @selected_project ||= params[:project_id].present? ? Project.find(params[:project_id]) : Project.default
      end

      def owned_stream
        message = @current_agent.messages.find_by(id: params[:id])
        unless message
          render json: { error: "Streaming message not found." }, status: :not_found
          return
        end
        unless message.streaming?
          render json: { errors: [ "Completed messages are immutable" ] }, status: :unprocessable_entity
          return
        end
        message
      end

      def save_or_error(message, status = :ok)
        if message.save
          render json: Api::MessagesController.serialize(message), status: status
        else
          render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end
  end
end
