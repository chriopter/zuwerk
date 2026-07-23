class ProjectAgentsController < ApplicationController
  before_action :require_human!

  def index
    @project = workspace_projects.find(params[:id])
    @hosted_agents = HostedAgent.includes(:user).order(:created_at)
    @panes = @project.agent_terminal_panes.includes(hosted_agent: :user).order(:created_at)
  end
end
