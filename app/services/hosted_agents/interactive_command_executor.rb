require "open3"

module HostedAgents
  class InteractiveCommandExecutor
    def open(*argv)
      Open3.popen2e(*argv)
    end

    def open_separate(*argv)
      Open3.popen3(*argv)
    end
  end
end
