module Api
  class TodoCommentsController < BaseController
    def index
      render json: todo.comments.includes(:author, :rich_text_body).order(:created_at).map { |comment| serialize(comment) }
    end

    def create
      return create_for_event if params[:event_id].present?

      comment = todo.comments.new(author: @current_agent, body: params[:body])
      save(comment)
    end

    private

    def project
      @project ||= Project.find(params[:project_id])
    end

    def todo
      @todo ||= project.todos.find(params[:todo_id])
    end

    def create_for_event
      event = @current_agent.agent_events.find_by!(public_id: params[:event_id])
      unless event.event_type.in?(%w[todo_assigned comment_mentioned]) && event.todo == todo
        raise ActiveRecord::RecordNotFound.new("AgentEvent not found", "AgentEvent")
      end

      event.with_lock do
        return render json: serialize(event.publication_comment), status: :ok if event.publication_comment

        save(todo.comments.new(author: @current_agent, body: params[:body], agent_event: event))
      end
    end

    def save(comment)
      if comment.save
        render json: serialize(comment), status: :created
      else
        render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def serialize(comment)
      {
        id: comment.id,
        todo_id: comment.todo_id,
        body: comment.body.to_plain_text,
        author: { id: comment.author.id, name: comment.author.name, kind: comment.author.kind },
        event_id: comment.agent_event&.public_id,
        created_at: comment.created_at.iso8601,
        updated_at: comment.updated_at.iso8601
      }
    end
  end
end
