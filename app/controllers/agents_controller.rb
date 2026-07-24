class AgentsController < ApplicationController
  before_action :require_human!

  def index
    @agents = User.agent.order(:name)
    @agent_profiles = AgentConnectors::Profiles.all
    @latest_prompt_events = AgentEvent
      .where(recipient: @agents)
      .where.not(prompt_snapshot: [ nil, "" ])
      .where.not(prompted_at: nil)
      .order(prompted_at: :desc, id: :desc)
      .each_with_object({}) { |event, events| events[event.recipient_id] ||= event }
  end
end
