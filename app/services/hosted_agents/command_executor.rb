require "open3"

module HostedAgents
  class CommandExecutor
    class CommandError < StandardError; end

    def run(*argv, input: nil)
      argv = isolated_podman_command(argv) if argv.first == "podman"
      output, status = Open3.capture2e(*argv, stdin_data: input.to_s)
      raise CommandError, output.strip unless status.success?

      output
    end

    private
      def isolated_podman_command(argv)
        [
          "systemd-run", "--scope", "--quiet", "--collect",
          "--unit=zuwerk-podman-#{SecureRandom.hex(8)}",
          *argv
        ]
      end
  end
end
