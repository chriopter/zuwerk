class TasksController < ApplicationController
  before_action :require_human!
  before_action :load_workspace
  before_action :set_task, only: %i[show edit update reorder]

  def index
    @focus_list = @project.task_lists.find(params[:list]) if params[:list].present?
    @lists = @focus_list ? [ @focus_list ] : @project.task_lists.order(:position, :id).to_a
    tasks = @project.tasks.includes(:assigned_agents).ordered.to_a
    @list_tasks = tasks.group_by(&:task_list_id)
    @unlisted_tasks = @focus_list ? [] : (@list_tasks.delete(nil) || [])
  end

  def show
    @comment = @task.comments.new
    InboxItem.find_by(user: current_user, trackable: @task)&.mark_read!
  end

  def new
    @task = @project.tasks.new(
      parent_id: params[:parent_id],
      task_list: selected_task_list,
      status: params.dig(:task, :status).presence || :open
    )
  end

  def create
    attributes = task_params
    @task = @project.tasks.new(creator: current_user)
    @task.assign_attributes(attributes.except(:parent_id))
    @task.parent = find_parent(attributes[:parent_id])
    @task.task_list ||= @task.parent&.task_list || @project.default_task_list
    @project.with_lock do
      @task.position = next_position(@task.task_list, @task.parent)
      @task.save!
    end
    if params[:return_to] == "board"
      redirect_to project_tasks_path(@project, adding: params[:adding].presence, list: params[:list].presence)
    else
      redirect_to project_task_path(@project, @task)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
    add_submission_error(error)
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    attributes = task_params
    Task.transaction do
      @task.update!(attributes.except(:parent_id, :task_list_id))
      if attributes.key?(:parent_id) || attributes.key?(:task_list_id)
        parent = attributes.key?(:parent_id) ? find_parent(attributes[:parent_id]) : @task.parent
        list = attributes.key?(:task_list_id) ? find_task_list(attributes[:task_list_id]) : @task.task_list
        list ||= parent&.task_list || @project.default_task_list
        position = parent == @task.parent && list == @task.task_list ? @task.position : next_position(list, parent)
        @task.move_to!(task_list: list, parent: parent, position: position)
      end
    end
    if @task.errors.empty?
      if params[:return_to] == "board"
        redirect_to project_tasks_path(@project, adding: params[:adding].presence, list: params[:list].presence)
      else
        redirect_to project_task_path(@project, @task)
      end
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
    add_submission_error(error)
    render :edit, status: :unprocessable_entity
  end

  def reorder
    raise ArgumentError, "position is required" unless params.key?(:position) || params.key?(:task_list_id)

    parent = params.key?(:parent_id) ? find_parent(params[:parent_id]) : @task.parent
    if params.key?(:task_list_id)
      raise ArgumentError, "task_list_id is required" if params[:task_list_id].blank?

      list = find_task_list(params[:task_list_id])
    else
      list = @task.task_list
    end
    position = params[:position].presence || next_position(list, parent)
    @task.move_to!(task_list: list, parent: parent, position: position)
    head :no_content
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, TypeError => error
    errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
    render json: { errors: errors }, status: :unprocessable_entity
  end

  private

  def load_workspace
    @project = Project.find(params[:project_id])
    @agents = User.agent.order(:name)
    @tasks = @project.tasks.includes(:assigned_agents).ordered
  end

  def set_task
    @task = @project.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title, :description, :status, :parent_id, :task_list_id)
  end

  def next_position(list, parent)
    siblings = parent ? parent.children : @project.tasks.roots.where(task_list: list)
    maximum = siblings.maximum(:position)
    maximum ? maximum + 1 : 0
  end

  def find_parent(parent_id)
    parent_id.present? ? @project.tasks.find(parent_id) : nil
  end

  def find_task_list(task_list_id)
    task_list_id.present? ? @project.task_lists.find(task_list_id) : nil
  end

  def selected_task_list
    find_task_list(params.dig(:task, :task_list_id)) || @project.default_task_list
  end

  def add_submission_error(error)
    @task ||= @project.tasks.new(creator: current_user)
    return if error.is_a?(ActiveRecord::RecordInvalid) && error.record == @task

    attribute = error.is_a?(ActiveRecord::RecordNotFound) ? :parent : :base
    @task.errors.add(attribute, error.is_a?(ActiveRecord::RecordNotFound) ? "is invalid" : error.message)
  end
end
