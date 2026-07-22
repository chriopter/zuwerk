class TodosController < ApplicationController
  before_action :require_human!
  before_action :load_workspace
  before_action :set_todo, only: %i[show edit update reorder]

  def index
    @todo = @project.todos.roots.ordered.first
    return redirect_to project_todo_path(@project, @todo) if @todo

    @todo = @project.todos.new
  end

  def show
    @comment = @todo.comments.new
  end

  def new
    @todo = @project.todos.new(parent_id: params[:parent_id])
  end

  def create
    @todo = @project.todos.new(todo_params.merge(creator: current_user))
    saved = @project.with_lock do
      @todo.position = next_position(@todo.parent)
      @todo.save
    end
    if saved
      redirect_to project_todo_path(@project, @todo)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = todo_params
    Todo.transaction do
      @todo.update!(attributes.except(:parent_id))
      if attributes.key?(:parent_id)
        parent = attributes[:parent_id].present? ? @project.todos.find(attributes[:parent_id]) : nil
        position = parent == @todo.parent ? @todo.position : (parent ? parent.children.count : @project.todos.roots.count)
        @todo.move_to!(parent: parent, position: position)
      end
    end
    if @todo.errors.empty?
      redirect_to project_todo_path(@project, @todo)
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    render :edit, status: :unprocessable_entity
  end

  def reorder
    parent = params[:parent_id].present? ? @project.todos.find(params[:parent_id]) : nil
    @todo.move_to!(parent: parent, position: params[:position])
    head :no_content
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, TypeError => error
    errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ error.message ]
    render json: { errors: errors }, status: :unprocessable_entity
  end

  private

  def load_workspace
    @project = Project.find(params[:project_id])
    @projects = Project.order(:name)
    @sidebar_agents = User.agent.includes(:hosted_agent).order(:name)
    @agents = User.agent.order(:name)
    @todos = @project.todos.includes(:assigned_agents).ordered
  end

  def set_todo
    @todo = @project.todos.find(params[:id])
  end

  def todo_params
    params.require(:todo).permit(:title, :description, :status, :parent_id)
  end

  def next_position(parent)
    siblings = parent ? parent.children : @project.todos.roots
    siblings.maximum(:position).to_i + 1
  end
end
