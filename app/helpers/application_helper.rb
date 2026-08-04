module ApplicationHelper
  def online_agents
    @online_agents ||= Current.account ? Current.account.agents : User.none
      .where.not(connector_connection_id: nil)
      .where("connector_heartbeat_at > ?", User::CONNECTOR_TTL.ago)
      .order(:name)
      .to_a
  end
end
