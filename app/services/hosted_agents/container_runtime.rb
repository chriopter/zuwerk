module HostedAgents
  class ContainerRuntime
    IMAGE = ENV.fetch("ZUWERK_AGENT_IMAGE", "zuwerk-agent:latest")

    def initialize(hosted_agent, executor: CommandExecutor.new)
      @hosted_agent = hosted_agent
      @executor = executor
    end

    def running?
      @executor.run(
        "podman", "inspect", "--format", "{{.State.Status}}", @hosted_agent.container_name
      ).strip == "running"
    rescue CommandExecutor::CommandError
      false
    end

    def provision
      @hosted_agent.update!(state: "provisioning", last_error: nil)
      if (container = existing_container)
        status, container_id = container
        @executor.run("podman", "start", @hosted_agent.container_name) unless status == "running"
        @hosted_agent.update!(container_id: container_id, state: "running", last_started_at: Time.current)
        return
      end

      output = @executor.run(
        "podman", "run", "-d",
        "--name", @hosted_agent.container_name,
        "--hostname", @hosted_agent.container_name,
        "--restart=unless-stopped",
        "--memory=4g",
        "--cpus=2",
        "--pids-limit=2048",
        "--security-opt=no-new-privileges",
        "--volume", "#{@hosted_agent.container_name}-home:/root",
        "--volume", "#{@hosted_agent.container_name}-workspace:/workspace",
        IMAGE,
        @hosted_agent.runtime
      )
      @hosted_agent.update!(container_id: output.strip, state: "running", last_started_at: Time.current)
    rescue CommandExecutor::CommandError => error
      fail_with(error)
    end

    def start
      lifecycle("start", "podman", "start", @hosted_agent.container_name)
    end

    def stop
      lifecycle("stop", "podman", "stop", "--time", "20", @hosted_agent.container_name)
    end

    def restart
      lifecycle("start", "podman", "restart", "--time", "20", @hosted_agent.container_name)
    end

    def remove
      @executor.run("podman", "rm", "--force", "--time", "20", @hosted_agent.container_name)
      @hosted_agent.destroy!
    end

    private
      def existing_container
        output = @executor.run(
          "podman", "inspect", "--format", "{{.State.Status}} {{.Id}}", @hosted_agent.container_name
        )
        output.split.first(2)
      rescue CommandExecutor::CommandError
        nil
      end

      def lifecycle(result, *argv)
        @executor.run(*argv)
        attributes = { state: result == "stop" ? "stopped" : "running", last_error: nil }
        attributes[result == "stop" ? :last_stopped_at : :last_started_at] = Time.current
        @hosted_agent.update!(attributes)
      rescue CommandExecutor::CommandError => error
        fail_with(error)
      end

      def fail_with(error)
        @hosted_agent.update!(state: "error", last_error: error.message.to_s.first(500))
        raise error
      end
  end
end
