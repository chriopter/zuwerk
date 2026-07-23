class AgentTerminalPanesController < ApplicationController
  class_attribute :runtime_factory, default: ->(pane) { HostedAgents::TerminalPaneRuntime.new(pane) }

  before_action :require_human!
  before_action :load_project
  before_action :load_pane, only: :destroy

  def create
    hosted_agent = HostedAgent.find(pane_params[:hosted_agent_id])
    pane = @project.agent_terminal_panes.create!(hosted_agent:, creator: current_user, name: pane_params[:name])
    runtime_factory.call(pane).create
    redirect_to agents_project_path(@project, anchor: "pane_#{pane.id}"), notice: "Terminal pane created."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, HostedAgents::CommandExecutor::CommandError => error
    pane&.destroy
    redirect_to agents_project_path(@project), alert: "Could not create terminal pane: #{error.message.to_s.first(240)}"
  end

  def destroy
    runtime_factory.call(@pane).destroy
    @pane.destroy!
    redirect_to agents_project_path(@project), notice: "Terminal pane closed."
  end

  private
    def load_project
      @project = workspace_projects.find(params[:project_id])
    end

    def load_pane
      @pane = @project.agent_terminal_panes.find(params[:id])
    end

    def pane_params
      params.require(:agent_terminal_pane).permit(:hosted_agent_id, :name)
    end
end
