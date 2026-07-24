module ApplicationHelper
  def online_agents
    User.agent.order(:name).select(&:external_connector_present?)
  end
end
