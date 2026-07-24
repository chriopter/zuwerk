module Api
  class TaskCommentsController < BaseController
    def index
      render json: task.comments.includes(:author, :rich_text_body).order(:created_at).map { |comment| serialize(comment) }
    end

    def create
      return create_for_event if params[:event_id].present?

      comment = task.comments.new(author: @current_agent, body: params[:body])
      save(comment)
    end

    private

    def project
      @project ||= Project.find(params[:project_id])
    end

    def task
      @task ||= project.tasks.find(params[:task_id])
    end

    def create_for_event
      event = @current_agent.agent_events.find_by!(public_id: params[:event_id])
      unless event.event_type.in?(%w[task_assigned task_comment_mentioned]) && event.task == task
        raise ActiveRecord::RecordNotFound.new("AgentEvent not found", "AgentEvent")
      end

      event.with_lock do
        return render json: serialize(event.publication_task_comment), status: :ok if event.publication_task_comment

        save(task.comments.new(author: @current_agent, body: params[:body], agent_event: event))
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
        task_id: comment.task_id,
        body: comment.body.to_plain_text,
        author: { id: comment.author.id, name: comment.author.name, kind: comment.author.kind },
        event_id: comment.agent_event&.public_id,
        created_at: comment.created_at.iso8601,
        updated_at: comment.updated_at.iso8601
      }
    end
  end
end
