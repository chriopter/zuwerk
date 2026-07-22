module Api
  class TodosController < BaseController
    def index
      render json: project.todos.includes(:creator, :rich_text_description).order(:created_at).map { |todo| serialize(todo) }
    end

    def show
      render json: serialize(todo)
    end

    def create
      attributes = todo_params
      item = project.todos.new(attributes.except(:parent_id, :position).merge(creator: @current_agent))
      project.with_lock do
        item.save!
        parent = attributes[:parent_id].present? ? project.todos.find(attributes[:parent_id]) : nil
        position = attributes[:position].presence || (parent ? parent.children.count : project.todos.roots.count)
        item.move_to!(parent: parent, position: position)
      end
      render json: serialize(item), status: :created
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, TypeError => error
      errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
      render json: { errors: errors }, status: :unprocessable_entity
    end

    def update
      attributes = todo_params
      project.with_lock do
        todo.update!(attributes.except(:parent_id, :position))
        if attributes.key?(:parent_id) || attributes.key?(:position)
          parent = attributes.key?(:parent_id) ? (attributes[:parent_id].present? ? project.todos.find(attributes[:parent_id]) : nil) : todo.parent
          position = attributes[:position].presence || (parent == todo.parent ? todo.position : (parent ? parent.children.count : project.todos.roots.count))
          todo.move_to!(parent: parent, position: position)
        end
      end
      render json: serialize(todo), status: :ok
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, TypeError => error
      errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
      render json: { errors: errors }, status: :unprocessable_entity
    end

    private
      def project
        @project ||= Project.find(params[:project_id])
      end

      def todo
        @todo ||= project.todos.find(params[:id])
      end

      def todo_params
        params.permit(:title, :description, :status, :parent_id, :position)
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
          parent_id: item.parent_id,
          position: item.position,
          ancestors: item.ancestors.map { |ancestor| { id: ancestor.id, title: ancestor.title } },
          children: item.children.ordered.map { |child| { id: child.id, title: child.title, status: child.status } },
          assigned_agents: item.assigned_agents.map { |agent| { id: agent.id, name: agent.name, handle: agent.handle } },
          comments: item.comments.includes(:author, :rich_text_body).order(:created_at).map do |comment|
            { id: comment.id, body: comment.body.to_plain_text, author: { id: comment.author.id, name: comment.author.name }, created_at: comment.created_at.iso8601 }
          end,
          creator: { id: item.creator.id, name: item.creator.name, kind: item.creator.kind },
          created_at: item.created_at.iso8601,
          updated_at: item.updated_at.iso8601
        }
      end
  end
end
