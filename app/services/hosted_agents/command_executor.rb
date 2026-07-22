require "open3"

module HostedAgents
  class CommandExecutor
    class CommandError < StandardError; end

    def run(*argv, input: nil)
      output, status = Open3.capture2e(*argv, stdin_data: input.to_s)
      raise CommandError, output.strip unless status.success?

      output
    end
  end
end
