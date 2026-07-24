class AgentsController < ApplicationController
  before_action :require_human!

  def index
    @agents = User.agent.order(:name)
    @agent_profiles = AgentConnectors::Profiles.all
  end
end
