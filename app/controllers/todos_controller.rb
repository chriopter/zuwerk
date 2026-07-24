class TodosController < ApplicationController
  before_action :require_human!
  before_action :load_workspace
  before_action :set_todo, only: %i[show edit update reorder]

  def index
    @focus_list = @project.todo_lists.find(params[:list]) if params[:list].present?
    @lists = @focus_list ? [ @focus_list ] : @project.todo_lists.order(:position, :id).to_a
    todos = @project.todos.includes(:assigned_agents).ordered.to_a
    @list_todos = todos.group_by(&:todo_list_id)
    @unlisted_todos = @focus_list ? [] : (@list_todos.delete(nil) || [])
  end

  def show
    @comment = @todo.comments.new
  end

  def new
    @todo = @project.todos.new(parent_id: params[:parent_id], status: params.dig(:todo, :status).presence || :open)
  end

  def create
    attributes = todo_params
    @todo = @project.todos.new(creator: current_user)
    @todo.assign_attributes(attributes.except(:parent_id))
    @todo.parent = find_parent(attributes[:parent_id])
    @project.with_lock do
      @todo.position = next_position(@todo.parent)
      @todo.save!
    end
    if params[:return_to] == "board"
      redirect_to project_todos_path(@project, adding: params[:adding].presence, list: params[:list].presence)
    else
      redirect_to project_todo_path(@project, @todo)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
    add_submission_error(error)
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    attributes = todo_params
    Todo.transaction do
      @todo.update!(attributes.except(:parent_id))
      if attributes.key?(:parent_id)
        parent = find_parent(attributes[:parent_id])
        position = parent == @todo.parent ? @todo.position : (parent ? parent.children.count : @project.todos.roots.count)
        @todo.move_to!(parent: parent, position: position)
      end
    end
    if @todo.errors.empty?
      if params[:return_to] == "board"
      redirect_to project_todos_path(@project, adding: params[:adding].presence, list: params[:list].presence)
    else
      redirect_to project_todo_path(@project, @todo)
    end
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
    add_submission_error(error)
    render :edit, status: :unprocessable_entity
  end

  def reorder
    if params[:position].present? || params[:parent_id].present? || !params.key?(:todo_list_id)
      parent = params[:parent_id].present? ? @project.todos.find(params[:parent_id]) : nil
      @todo.move_to!(parent: parent, position: params[:position])
    end
    if params.key?(:todo_list_id)
      list = params[:todo_list_id].present? ? @project.todo_lists.find(params[:todo_list_id]) : nil
      @todo.update!(todo_list: list)
    end
    head :no_content
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, TypeError => error
    errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
    render json: { errors: errors }, status: :unprocessable_entity
  end

  private

  def load_workspace
    @project = Project.find(params[:project_id])
    @agents = User.agent.order(:name)
    @todos = @project.todos.includes(:assigned_agents).ordered
  end

  def set_todo
    @todo = @project.todos.find(params[:id])
  end

  def todo_params
    params.require(:todo).permit(:title, :description, :status, :parent_id, :todo_list_id)
  end

  def next_position(parent)
    siblings = parent ? parent.children : @project.todos.roots
    maximum = siblings.maximum(:position)
    maximum ? maximum + 1 : 0
  end

  def find_parent(parent_id)
    parent_id.present? ? @project.todos.find(parent_id) : nil
  end

  def add_submission_error(error)
    @todo ||= @project.todos.new(creator: current_user)
    return if error.is_a?(ActiveRecord::RecordInvalid) && error.record == @todo

    attribute = error.is_a?(ActiveRecord::RecordNotFound) ? :parent : :base
    @todo.errors.add(attribute, error.is_a?(ActiveRecord::RecordNotFound) ? "is invalid" : error.message)
  end
end
