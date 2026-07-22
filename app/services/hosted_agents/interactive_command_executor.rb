require "open3"

module HostedAgents
  class InteractiveCommandExecutor
    def open(*argv)
      Open3.popen2e(*argv)
    end
  end
end
