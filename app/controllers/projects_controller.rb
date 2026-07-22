class ProjectsController < ApplicationController
  before_action :require_human!

  def create
    project = Project.new(project_params)
    if project.save
      project.room_setting
      redirect_to chat_project_path(project), notice: "Project created."
    else
      redirect_to root_path, alert: project.errors.full_messages.to_sentence
    end
  end

  private
    def project_params
      params.require(:project).permit(:name)
    end
end
