module HostedAgents
  class TerminalPaneRuntime
    def initialize(pane, executor: CommandExecutor.new)
      @pane = pane
      @hosted_agent = pane.hosted_agent
      @executor = executor
    end

    def create
      raise ArgumentError, "Agent is not running" unless @hosted_agent.running?
      return @pane if exists?

      @executor.run(
        "podman", "exec", @hosted_agent.container_name,
        "tmux", "new-session", "-d", "-s", @pane.tmux_window,
        "-c", "/workspace", runtime_command
      )
      @pane
    end

    def exists?
      @executor.run("podman", "exec", @hosted_agent.container_name, "tmux", "has-session", "-t", @pane.tmux_window)
      true
    rescue CommandExecutor::CommandError
      false
    end

    def destroy
      @executor.run(
        "podman", "exec", @hosted_agent.container_name,
        "tmux", "kill-session", "-t", @pane.tmux_window
      )
    rescue CommandExecutor::CommandError
      nil
    end

    private
      def runtime_command
        @hosted_agent.runtime == "codex" ? "codex" : "claude"
      end
  end
end
