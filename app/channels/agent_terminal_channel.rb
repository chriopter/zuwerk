class AgentTerminalChannel < ApplicationCable::Channel
  class_attribute :bridge_factory, default: ->(hosted_agent, terminal_pane = nil) { HostedAgents::TerminalBridge.new(hosted_agent, terminal_pane:) }
  class_attribute :runtime_factory, default: ->(hosted_agent) { HostedAgents::ContainerRuntime.new(hosted_agent) }
  class_attribute :pane_runtime_factory, default: ->(pane) { HostedAgents::TerminalPaneRuntime.new(pane) }

  def subscribed
    unless connection.current_user&.human?
      reject
      return
    end

    agent = User.agent.find(params[:agent_id])
    hosted_agent = HostedAgent.find_by!(user: agent)
    terminal_pane = load_terminal_pane(hosted_agent)
    runtime = runtime_factory.call(hosted_agent)
    actually_running = runtime.running?
    if terminal_pane
      unless hosted_agent.running? && actually_running && pane_runtime_factory.call(terminal_pane).exists?
        reject
        return
      end
    else
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
    end

    @bridge = terminal_pane ? bridge_factory.call(hosted_agent, terminal_pane) : bridge_factory.call(hosted_agent)
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

  private
    def load_terminal_pane(hosted_agent)
      return if params[:pane_id].blank? && params[:project_id].blank?

      project = ProjectAccess.new(connection.current_user).projects.find(params[:project_id])
      project.agent_terminal_panes.find_by!(id: params[:pane_id], hosted_agent: hosted_agent)
    end
end
