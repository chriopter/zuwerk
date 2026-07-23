module HostedAgents
  class TerminalBridge
    MAX_INPUT = 4_096
    SESSION = "agent"

    def initialize(hosted_agent, executor: CommandExecutor.new, interactive_executor: InteractiveCommandExecutor.new, terminal_pane: nil)
      @hosted_agent = hosted_agent
      @executor = executor
      @interactive_executor = interactive_executor
      @terminal_pane = terminal_pane
    end

    def start(rows: 24, columns: 80, &on_output)
      raise ArgumentError, "Agent is not running" unless @hosted_agent.running?

      rows = rows.to_i.clamp(10, 200)
      columns = columns.to_i.clamp(20, 400)
      runtime_command = @hosted_agent.runtime == "codex" ? "codex" : "claude"
      if @terminal_pane
        attach_command = "stty rows \"$ZUWERK_ROWS\" cols \"$ZUWERK_COLUMNS\"; exec tmux attach-session -t #{terminal_target}"
      else
        attach_command = "tmux has-session -t agent 2>/dev/null || tmux new-session -d -s agent -c /workspace 'exec #{runtime_command}'; stty rows \"$ZUWERK_ROWS\" cols \"$ZUWERK_COLUMNS\"; exec tmux attach-session -t agent"
      end

      argv = [
        "podman", "exec", "-i",
        "-e", "TERM=xterm-256color",
        "-e", "ZUWERK_ROWS=#{rows}",
        "-e", "ZUWERK_COLUMNS=#{columns}",
        @hosted_agent.container_name,
        "script", "-qfec", attach_command, "/dev/null"
      ]
      @writer, @reader, @wait_thread = @interactive_executor.open(*argv, pgroup: true)
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
        "tmux", "resize-window", "-t", resize_target, "-x", columns.to_s, "-y", rows.to_s
      )
    end

    def close
      @reader&.close unless @reader&.closed?
      @writer&.close unless @writer&.closed?
      Process.kill("TERM", -@wait_thread.pid) if @wait_thread
    rescue Errno::EBADF, Errno::ESRCH, IOError
      nil
    ensure
      @reader_thread&.kill unless @reader_thread == Thread.current
    end

    private
      def terminal_target
        @terminal_pane ? @terminal_pane.tmux_window : SESSION
      end

      def resize_target
        "#{terminal_target}:0"
      end

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
