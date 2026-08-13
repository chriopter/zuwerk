class AgentsController < ApplicationController
  before_action :require_human!
  before_action :authorize_account
  before_action :set_agent, except: :index

  def index
    @agents = current_account_agents.order(:name)
    @agent_profiles = AgentConnectors::Profiles.all
    @prompt_template = AgentConnectors::PromptTemplates.master
    @prompt_types = AgentConnectors::PromptTemplates.types
    @prompt_previews = AgentConnectors::PromptTemplates.previews
    @sessions_by_agent = AgentSession
      .where(agent: @agents)
      .includes(:project, :context)
      .recent_first
      .group_by(&:agent_id)
    @latest_events_by_agent = AgentEvent.where(recipient: @agents).order(created_at: :desc, id: :desc).group_by(&:recipient_id).transform_values(&:first)
  end

  def cancel
    event = @agent.agent_events.where(state: %w[queued running waiting_for_approval]).order(created_at: :desc, id: :desc).first
    event&.transition_to!("cancelled")
    redirect_to agents_path, notice: event ? "#{@agent.name}'s turn was cancelled." : "#{@agent.name} has no active turn."
  end

  def reconnect
    ActionCable.server.remote_connections.where(current_user: @agent).disconnect(reconnect: true)
    redirect_to agents_path, notice: "#{@agent.name} was asked to reconnect."
  end

  def retry
    event = @agent.agent_events.where(state: "failed").order(created_at: :desc, id: :desc).first
    event&.retry!
    redirect_to agents_path, notice: event ? "#{@agent.name}'s last failed turn was queued again." : "#{@agent.name} has no failed turn to retry."
  end

  private
    def authorize_account
      authorize Current.account, :show?
    end

    def set_agent
      @agent = current_account_agents.find(params[:id])
    end
end
