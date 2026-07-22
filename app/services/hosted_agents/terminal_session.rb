module HostedAgents
  class TerminalSession
    MAX_INPUT = 4_096

    def initialize(hosted_agent, executor: CommandExecutor.new)
      @hosted_agent = hosted_agent
      @executor = executor
    end

    def capture
      @executor.run(
        "podman", "exec", @hosted_agent.container_name,
        "tmux", "capture-pane", "-p", "-e", "-t", "agent:0.0", "-S", "-200"
      )
    end

    def write(input)
      raise ArgumentError, "Input is too long" if input.to_s.bytesize > MAX_INPUT

      buffer_name = "zuwerk-terminal-#{SecureRandom.hex(8)}"
      @hosted_agent.with_lock do
        @executor.run(
          "podman", "exec", "-i", @hosted_agent.container_name,
          "tmux", "load-buffer", "-b", buffer_name, "-",
          input: input.to_s
        )
        @executor.run(
          "podman", "exec", @hosted_agent.container_name,
          "tmux", "paste-buffer", "-b", buffer_name, "-d", "-t", "agent:0.0"
        )
      end
    end
  end
end
