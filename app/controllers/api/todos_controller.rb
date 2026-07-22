module Api
  class TodosController < BaseController
    def index
      render json: project.todos.includes(:creator, :rich_text_description).order(:created_at).map { |todo| serialize(todo) }
    end

    def show
      render json: serialize(todo)
    end

    def create
      item = project.todos.new(todo_params.merge(creator: @current_agent))
      save_or_render_errors(item, :created)
    end

    def update
      todo.assign_attributes(todo_params)
      save_or_render_errors(todo, :ok)
    end

    private
      def project
        @project ||= Project.find(params[:project_id])
      end

      def todo
        @todo ||= project.todos.find(params[:id])
      end

      def todo_params
        params.permit(:title, :description, :status)
      end

      def save_or_render_errors(item, status)
        if item.save
          render json: serialize(item), status: status
        else
          render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def serialize(item)
        {
          id: item.id,
          project: { id: item.project.id, name: item.project.name },
          title: item.title,
          description: item.description.to_plain_text,
          status: item.status,
          creator: { id: item.creator.id, name: item.creator.name, kind: item.creator.kind },
          created_at: item.created_at.iso8601,
          updated_at: item.updated_at.iso8601
        }
      end
  end
end
