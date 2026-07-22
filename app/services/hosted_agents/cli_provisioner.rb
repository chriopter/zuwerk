require "json"
require "tempfile"

module HostedAgents
  class CliProvisioner
    DEFAULT_SERVER = "http://host.containers.internal:3100"

    def initialize(hosted_agent, executor: CommandExecutor.new, server: ENV.fetch("ZUWERK_INTERNAL_URL", DEFAULT_SERVER))
      @hosted_agent = hosted_agent
      @executor = executor
      @server = server
    end

    def call
      identity = @hosted_agent.user
      identity.with_lock do
        return if current_config_matches?(identity)

        token = SecureRandom.urlsafe_base64(32)
        copy_config(token)
        identity.update!(api_token_digest: User.digest(token))
      end
    end

    def verify!
      output = @executor.run("podman", "exec", @hosted_agent.container_name, "zuwerk", "projects", "list")
      projects = JSON.parse(output)
      raise CommandExecutor::CommandError, "Zuwerk CLI returned an invalid project list" unless projects.is_a?(Array)

      true
    rescue JSON::ParserError
      raise CommandExecutor::CommandError, "Zuwerk CLI returned invalid JSON"
    end

    private
      def current_config_matches?(identity)
        return false if identity.api_token_digest.blank?

        raw = @executor.run(
          "podman", "exec", @hosted_agent.container_name,
          "cat", "/root/.config/zuwerk/config.json"
        )
        config = JSON.parse(raw)
        token = config.fetch("api_token")
        config.fetch("server_url") == @server && ActiveSupport::SecurityUtils.secure_compare(User.digest(token), identity.api_token_digest)
      rescue CommandExecutor::CommandError, JSON::ParserError, KeyError
        false
      end

      def copy_config(token)
        Tempfile.create([ "zuwerk-cli", ".json" ]) do |file|
          file.chmod(0o600)
          file.write(JSON.generate(server_url: @server, api_token: token))
          file.flush

          @executor.run("podman", "exec", @hosted_agent.container_name, "mkdir", "-p", "/root/.config/zuwerk")
          @executor.run("podman", "cp", file.path, "#{@hosted_agent.container_name}:/root/.config/zuwerk/config.json")
          @executor.run("podman", "exec", @hosted_agent.container_name, "chmod", "0600", "/root/.config/zuwerk/config.json")
        end
      end
  end
end
