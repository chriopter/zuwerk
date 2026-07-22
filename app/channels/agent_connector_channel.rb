class AgentConnectorChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user&.agent?

    @connection_id = SecureRandom.uuid
    @transport = AgentConnectors.registry.register(current_user.id) do |line|
      transmit({ type: "acp", line: line })
    end
    current_user.register_connector!(@connection_id)
    @lifecycle = AgentConnectors::Lifecycle.new(agent_id: current_user.id, connection_id: @connection_id, transport: @transport).start
  end

  def receive(data)
    case data["type"] || data[:type]
    when "acp"
      @transport.receive(data["line"] || data[:line])
    when "heartbeat"
      return unless AgentConnectors.registry.fetch(current_user.id)&.equal?(@transport)
      current_user.heartbeat_connector!(@connection_id)
      current_user.update_columns(heartbeat_at: Time.current, updated_at: Time.current) if current_user.heartbeat_at.nil? || current_user.heartbeat_at < 15.seconds.ago
    end
  rescue AgentConnectors::Transport::Error => error
    Rails.logger.warn("Agent connector #{current_user&.id} closed: #{error.class}: #{error.message}")
    stop_all_streams
    disconnect_connector
  end

  def unsubscribed
    return unless current_user&.agent?

    disconnect_connector
  end

  private
    def disconnect_connector
      AgentConnectors.registry.unregister(current_user.id, @transport)
      @lifecycle&.stop
      current_user.clear_connector!(@connection_id) if @connection_id
    end
end
