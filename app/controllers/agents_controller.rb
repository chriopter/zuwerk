class AgentsController < ApplicationController
  before_action :require_human!

  def index
    @agents = User.agent.order(:name)
    @agent_profiles = AgentConnectors::Profiles.all
    @prompt_template = AgentConnectors::PromptTemplates.master
    @prompt_types = AgentConnectors::PromptTemplates.types
    @prompt_previews = AgentConnectors::PromptTemplates.previews
    @sessions_by_agent = AgentSession
      .where(agent: @agents)
      .includes(:project, :context)
      .recent_first
      .group_by(&:agent_id)
  end
end
