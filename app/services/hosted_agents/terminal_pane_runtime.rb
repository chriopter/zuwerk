module HostedAgents
  class TerminalPaneRuntime
    def initialize(pane, executor: CommandExecutor.new, repository_url: ENV["ZUWERK_AGENT_REPOSITORY_URL"])
      @pane = pane
      @hosted_agent = pane.hosted_agent
      @executor = executor
      @repository_url = repository_url.presence
    end

    def create
      raise ArgumentError, "Hosted agent must be running" unless @hosted_agent.running?

      bootstrap_workspace
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
      def bootstrap_workspace
        return if @repository_url.blank? || workspace_repository?

        @executor.run(
          "podman", "exec", @hosted_agent.container_name,
          "git", "clone", @repository_url, "/workspace"
        )
      end

      def workspace_repository?
        @executor.run(
          "podman", "exec", @hosted_agent.container_name,
          "git", "-C", "/workspace", "rev-parse", "--is-inside-work-tree"
        )
        true
      rescue CommandExecutor::CommandError
        false
      end

      def runtime_command
        @hosted_agent.runtime == "codex" ? "codex" : "claude"
      end
  end
end
