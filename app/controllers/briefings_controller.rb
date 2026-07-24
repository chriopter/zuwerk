class BriefingsController < ApplicationController
  before_action :require_human!
  before_action :load_project
  before_action :load_briefing, only: %i[show edit update run_now toggle]
  before_action :load_agents, only: %i[show new create edit update]

  def index
    @briefings = @project.briefings
      .recently_active
      .includes(:agent, comments: [ :author, :rich_text_body ])
  end

  def show
    @comment = @briefing.comments.new
    @comments = @briefing.comments.published.chronologically.includes(:author, :rich_text_body, reactions: :author)
    @latest_run = @briefing.comments.where.not(scheduled_for: nil).includes(:agent_event).order(scheduled_for: :desc, id: :desc).first
    InboxItem.find_by(user: current_user, trackable: @briefing)&.mark_read!
  end

  def new
    @briefing = @project.briefings.new(frequency: "weekly")
  end

  def create
    @briefing = @project.briefings.new(briefing_params.merge(creator: current_user, agent: selected_agent))
    if @briefing.save
      redirect_to project_briefing_path(@project, @briefing), notice: "Briefing created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @briefing.update(briefing_params.merge(agent: selected_agent))
      redirect_to project_briefing_path(@project, @briefing), notice: "Briefing updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def run_now
    @briefing.run_now!
    redirect_to project_briefing_path(@project, @briefing), notice: "Briefing run queued."
  end

  def toggle
    @briefing.active? ? @briefing.pause! : @briefing.resume!
    redirect_to project_briefing_path(@project, @briefing), notice: @briefing.active? ? "Briefing resumed." : "Briefing paused."
  end

  private

  def load_project
    @project = Project.find(params[:project_id])
  end

  def load_briefing
    @briefing = @project.briefings.find(params[:id])
  end

  def load_agents
    @agents = User.agent.order(:name)
  end

  def selected_agent
    @agents.find(params.require(:briefing).require(:agent_id))
  end

  def briefing_params
    params.require(:briefing).permit(:title, :frequency, :prompt)
  end
end
