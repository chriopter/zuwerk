module ApplicationHelper
  def online_agents_count
    User.agent.count(&:external_connector_present?)
  end
end
