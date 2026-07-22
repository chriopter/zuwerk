class ProjectsController < ApplicationController
  before_action :route_first_run
  before_action :require_human!

  def index
    @projects = Project.includes(:todos).order(:name)
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
