class AgentTerminalChannel < ApplicationCable::Channel
  class_attribute :bridge_factory, default: ->(hosted_agent) { HostedAgents::TerminalBridge.new(hosted_agent) }
  class_attribute :runtime_factory, default: ->(hosted_agent) { HostedAgents::ContainerRuntime.new(hosted_agent) }

  def subscribed
    agent = User.agent.find(params[:agent_id])
    hosted_agent = HostedAgent.find_by!(user: agent)
    runtime = runtime_factory.call(hosted_agent)
    actually_running = runtime.running?
    if (hosted_agent.running? || hosted_agent.state == "error") && !actually_running
      runtime.provision
      actually_running = runtime.running?
    end
    if hosted_agent.state == "error" && actually_running
      hosted_agent.update!(state: "running", last_error: nil)
    end
    hosted_agent.reload
    unless hosted_agent.running? && actually_running
      reject
      return
    end

    @bridge = bridge_factory.call(hosted_agent)
    @bridge.start(rows: params[:rows], columns: params[:columns]) do |output|
      transmit({ type: "output", data: output })
    end
    transmit({ type: "ready" })
  rescue ActiveRecord::RecordNotFound, ArgumentError, HostedAgents::CommandExecutor::CommandError
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
