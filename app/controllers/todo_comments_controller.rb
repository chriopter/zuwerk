class TodoCommentsController < ApplicationController
  before_action :require_human!
  before_action :load_records
  before_action :set_comment, only: %i[edit update destroy]
  before_action :ensure_author!, only: %i[edit update destroy]

  def create
    @comment = @todo.comments.new(comment_params.merge(author: current_user))
    if @comment.save
      redirect_to project_todo_path(@project, @todo, anchor: "todo_comment_#{@comment.id}")
    else
      load_workspace
      render "todos/show", status: :unprocessable_entity
    end
  end

  def edit
    load_workspace
  end

  def update
    if @comment.update(comment_params)
      redirect_to project_todo_path(@project, @todo, anchor: "todo_comment_#{@comment.id}")
    else
      load_workspace
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @comment.destroy!
    redirect_to project_todo_path(@project, @todo)
  end

  private

  def load_records
    @project = Project.find(params[:project_id])
    @todo = @project.todos.find(params[:todo_id])
  end

  def set_comment
    @comment = @todo.comments.find(params[:id])
  end

  def ensure_author!
    return if @comment.author == current_user

    head :forbidden
  end

  def comment_params
    params.require(:todo_comment).permit(:body)
  end

  def load_workspace
    @projects = Project.order(:name)
    @sidebar_agents = User.agent.includes(:hosted_agent).order(:name)
    @agents = User.agent.order(:name)
    @todos = @project.todos.ordered
  end
end
