module Api
  class TasksController < BaseController
    def index
      render json: project.tasks.includes(:creator, :rich_text_description).order(:created_at).map { |task| serialize(task) }
    end

    def show
      render json: serialize(task)
    end

    def create
      attributes = task_params
      parent = attributes[:parent_id].present? ? project.tasks.find(attributes[:parent_id]) : nil
      list = attributes[:task_list_id].present? ? project.task_lists.find(attributes[:task_list_id]) : parent&.task_list || project.default_task_list
      item = project.tasks.new(attributes.except(:parent_id, :position).merge(creator: @current_agent, task_list: list))
      project.with_lock do
        item.save!
        position = attributes[:position].presence || (parent ? parent.children.count : project.tasks.roots.where(task_list: list).count)
        item.move_to!(task_list: list, parent: parent, position: position)
      end
      render json: serialize(item), status: :created
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, TypeError => error
      errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
      render json: { errors: errors }, status: :unprocessable_entity
    end

    def update
      attributes = task_params
      project.with_lock do
        task.update!(attributes.except(:parent_id, :position, :task_list_id))
        if attributes.key?(:parent_id) || attributes.key?(:position) || attributes.key?(:task_list_id)
          parent = attributes.key?(:parent_id) ? (attributes[:parent_id].present? ? project.tasks.find(attributes[:parent_id]) : nil) : task.parent
          list = attributes.key?(:task_list_id) ? project.task_lists.find(attributes[:task_list_id]) : task.task_list
          position = attributes[:position].presence || (parent == task.parent && list == task.task_list ? task.position : (parent ? parent.children.count : project.tasks.roots.where(task_list: list).count))
          task.move_to!(task_list: list, parent: parent, position: position)
        end
      end
      render json: serialize(task), status: :ok
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, TypeError => error
      errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
      render json: { errors: errors }, status: :unprocessable_entity
    end

    private
      def project
        @project ||= Project.find(params[:project_id])
      end

      def task
        @task ||= project.tasks.find(params[:id])
      end

      def task_params
        params.permit(:title, :description, :status, :parent_id, :position, :task_list_id)
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
          task_list_id: item.task_list_id,
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
