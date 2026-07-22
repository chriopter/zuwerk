class AgentTerminalChannel < ApplicationCable::Channel
  class_attribute :bridge_factory, default: ->(hosted_agent) { HostedAgents::TerminalBridge.new(hosted_agent) }

  def subscribed
    agent = User.agent.find(params[:agent_id])
    hosted_agent = HostedAgent.find_by!(user: agent)
    unless hosted_agent.running?
      reject
      return
    end

    @bridge = bridge_factory.call(hosted_agent)
    @bridge.start(rows: params[:rows], columns: params[:columns]) do |output|
      transmit({ type: "output", data: output })
    end
    transmit({ type: "ready" })
  rescue ActiveRecord::RecordNotFound, ArgumentError
    reject
  end

  def receive(data)
    case data["type"]
    when "input"
      @bridge&.write(data["data"])
    when "resize"
      @bridge&.resize(rows: data["rows"], columns: data["columns"])
    end
  rescue ArgumentError => error
    transmit({ type: "error", message: error.message })
  end

  def unsubscribed
    @bridge&.close
  end
end
