class BoardAutomationsController < ApplicationController
  before_action :require_human!
  before_action :load_project
  before_action :load_automation, only: %i[show edit update run_now toggle]
  before_action :load_agents, only: %i[new create edit update]

  def new
    @automation = @project.board_automations.new(cadence: "weekly")
  end

  def create
    @automation = @project.board_automations.new(automation_params.merge(creator: current_user, agent: selected_agent))
    if @automation.save
      redirect_to project_board_automation_path(@project, @automation), notice: "Board automation created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @posts = @automation.board_posts.includes(:agent_event).order(scheduled_for: :desc, id: :desc).limit(20)
  end

  def edit
  end

  def update
    if @automation.update(automation_params.merge(agent: selected_agent))
      redirect_to project_board_automation_path(@project, @automation), notice: "Board automation updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def run_now
    @automation.run_now!
    redirect_to project_board_automation_path(@project, @automation), notice: "Board run queued."
  end

  def toggle
    @automation.active? ? @automation.pause! : @automation.resume!
    redirect_to project_board_automation_path(@project, @automation), notice: @automation.active? ? "Board automation resumed." : "Board automation paused."
  end

  private

  def load_project
    @project = Project.find(params[:project_id])
  end

  def load_automation
    @automation = @project.board_automations.find(params[:id])
  end

  def load_agents
    @agents = User.agent.joins(:hosted_agent).order(:name)
  end

  def selected_agent
    @agents.find(params.require(:board_automation).require(:agent_id))
  end

  def automation_params
    params.require(:board_automation).permit(:title, :cadence, :prompt)
  end
end
