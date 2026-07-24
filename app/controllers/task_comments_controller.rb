class TaskCommentsController < ApplicationController
  before_action :require_human!
  before_action :load_records
  before_action :set_comment, only: %i[edit update destroy]
  before_action :ensure_author!, only: %i[edit update destroy]

  def create
    @comment = @task.comments.new(comment_params.merge(author: current_user))
    if @comment.save
      redirect_to project_task_path(@project, @task, anchor: "task_comment_#{@comment.id}")
    else
      load_workspace
      render "tasks/show", status: :unprocessable_entity
    end
  end

  def edit
    load_workspace
  end

  def update
    if @comment.update(comment_params)
      redirect_to project_task_path(@project, @task, anchor: "task_comment_#{@comment.id}")
    else
      load_workspace
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @comment.destroy!
    redirect_to project_task_path(@project, @task)
  end

  private

  def load_records
    @project = Project.find(params[:project_id])
    @task = @project.tasks.find(params[:task_id])
  end

  def set_comment
    @comment = @task.comments.find(params[:id])
  end

  def ensure_author!
    return if @comment.author == current_user

    head :forbidden
  end

  def comment_params
    params.require(:task_comment).permit(:body)
  end

  def load_workspace
    @agents = User.agent.order(:name)
    @tasks = @project.tasks.ordered
  end
end
