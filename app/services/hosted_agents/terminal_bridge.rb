module HostedAgents
  class TerminalBridge
    MAX_INPUT = 4_096
    SESSION = "agent"

    def initialize(hosted_agent, executor: CommandExecutor.new, interactive_executor: InteractiveCommandExecutor.new)
      @hosted_agent = hosted_agent
      @executor = executor
      @interactive_executor = interactive_executor
    end

    def start(rows: 24, columns: 80, &on_output)
      raise ArgumentError, "Agent is not running" unless @hosted_agent.running?

      rows = rows.to_i.clamp(10, 200)
      columns = columns.to_i.clamp(20, 400)
      attach_command = 'stty rows "$ZUWERK_ROWS" cols "$ZUWERK_COLUMNS"; exec tmux attach-session -t agent'

      argv = [
        "podman", "exec", "-i",
        "-e", "TERM=xterm-256color",
        "-e", "ZUWERK_ROWS=#{rows}",
        "-e", "ZUWERK_COLUMNS=#{columns}",
        @hosted_agent.container_name,
        "script", "-qfec", attach_command, "/dev/null"
      ]
      @writer, @reader, @wait_thread = @interactive_executor.open(*argv)
      @reader_thread = Thread.new { read_output(&on_output) }
      self
    end

    def write(input)
      data = input.to_s
      raise ArgumentError, "Input is too long" if data.bytesize > MAX_INPUT

      @writer.write(data)
      @writer.flush
    end

    def resize(rows:, columns:)
      rows = rows.to_i.clamp(10, 200)
      columns = columns.to_i.clamp(20, 400)
      @executor.run(
        "podman", "exec", @hosted_agent.container_name,
        "tmux", "resize-window", "-t", "#{SESSION}:0", "-x", columns.to_s, "-y", rows.to_s
      )
    end

    def close
      @reader&.close unless @reader&.closed?
      @writer&.close unless @writer&.closed?
      Process.kill("TERM", @wait_thread.pid) if @wait_thread
    rescue Errno::EBADF, Errno::ESRCH, IOError
      nil
    ensure
      @reader_thread&.kill unless @reader_thread == Thread.current
    end

    private
      def read_output
        loop do
          chunk = @reader.readpartial(16_384)
          yield chunk.force_encoding(Encoding::UTF_8).scrub
        end
      rescue EOFError, Errno::EIO, IOError
        nil
      end
  end
end
