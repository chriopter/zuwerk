class AgentConnectorChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user&.agent?

    @transport = AgentConnectors.registry.register(current_user.id) do |line|
      transmit({ type: "acp", line: line })
    end
  end

  def receive(data)
    case data["type"] || data[:type]
    when "acp"
      @transport.receive(data["line"] || data[:line])
    when "heartbeat"
      return unless AgentConnectors.registry.fetch(current_user.id)&.equal?(@transport)
      current_user.update_columns(heartbeat_at: Time.current, updated_at: Time.current) if current_user.heartbeat_at.nil? || current_user.heartbeat_at < 15.seconds.ago
    end
  rescue AgentConnectors::Transport::Error
    stop_all_streams
    AgentConnectors.registry.unregister(current_user.id, @transport)
  end

  def unsubscribed
    AgentConnectors.registry.unregister(current_user.id, @transport) if current_user&.agent?
  end
end
