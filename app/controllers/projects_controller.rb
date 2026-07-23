class ProjectsController < ApplicationController
  before_action :route_first_run
  before_action :require_human!

  def index
    @projects = Project.includes(:todos).order(:name)
  end

  def show
    @project = Project.includes(:todos).find(params[:id])
    @recent_todos = @project.todos.reject(&:completed?).sort_by { |todo| [ todo.updated_at, todo.id ] }.reverse.first(4)
    @recent_messages = @project.messages.includes(:author).order(created_at: :desc, id: :desc).limit(3)
  end

  def create
    project = Project.new(project_params)
    if project.save
      project.room_setting
      redirect_to projects_path, notice: "Project created."
    else
      redirect_to root_path, alert: project.errors.full_messages.to_sentence
    end
  end

  private
    def route_first_run
      redirect_to new_onboarding_path unless User.human.exists?
    end

    def project_params
      params.require(:project).permit(:name)
    end
end
