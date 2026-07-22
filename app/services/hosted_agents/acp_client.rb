require "json"
require "timeout"

module HostedAgents
  class AcpClient
    class Error < StandardError; end

    CLIENT_INFO = { name: "zuwerk", version: "1" }.freeze
    CLIENT_CAPABILITIES = {
      fs: { readTextFile: true, writeTextFile: true },
      terminal: true
    }.freeze

    def initialize(hosted_agent, executor: InteractiveCommandExecutor.new)
      @hosted_agent = hosted_agent
      @mutex = Mutex.new
      @next_id = 0
      command = hosted_agent.claude? ? "claude-agent-acp" : "codex-acp"
      argv = [ "podman", "exec", "-i", hosted_agent.container_name, command ]
      @stdin, @stdout, @stderr, @wait_thread = executor.open_separate(*argv)
      @stderr_thread = Thread.new do
        @stderr.each_line { |line| Rails.logger.warn("ACP #{hosted_agent.id}: #{line.strip}") }
      rescue IOError
        nil
      end
      request("initialize", {
        protocolVersion: 1,
        clientCapabilities: CLIENT_CAPABILITIES,
        clientInfo: CLIENT_INFO
      })
    rescue => error
      close
      raise Error, "Could not start ACP adapter: #{error.message}"
    end

    def alive?
      @wait_thread&.alive? && !@stdin&.closed?
    end

    def new_session
      result = request("session/new", { cwd: "/workspace", mcpServers: [] })
      session_id = result.fetch("sessionId")
      request("session/set_config_option", { sessionId: session_id, configId: "mode", value: session_mode })
      session_id
    end

    def load_session(session_id)
      request("session/load", { sessionId: session_id, cwd: "/workspace", mcpServers: [] })
      session_id
    end

    def prompt(session_id, text, &on_chunk)
      request(
        "session/prompt",
        { sessionId: session_id, prompt: [ { type: "text", text: text } ] },
        timeout: 300,
        &on_chunk
      )
    end

    def ping(session_id)
      request("session/set_config_option", { sessionId: session_id, configId: "mode", value: session_mode })
      true
    end

    def close
      @stdin&.close unless @stdin&.closed?
      @stdout&.close unless @stdout&.closed?
      @stderr&.close unless @stderr&.closed?
      Process.kill("TERM", @wait_thread.pid) if @wait_thread&.alive?
      @stderr_thread&.kill
    rescue IOError, Errno::ESRCH
      nil
    end

    private
      def session_mode
        @hosted_agent.runtime == "codex" ? "agent-full-access" : "auto"
      end

      def request(method, params = {}, timeout: 30, &on_chunk)
        @mutex.synchronize do
          raise Error, "ACP adapter is not running" unless alive?

          id = (@next_id += 1)
          write(jsonrpc: "2.0", id: id, method: method, params: params)
          read_response(id, timeout:, &on_chunk)
        end
      end

      def read_response(expected_id, timeout:)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Error, "ACP request timed out" unless remaining.positive? && IO.select([ @stdout ], nil, nil, remaining)

          line = @stdout.gets
          raise Error, "ACP adapter exited" unless line
          raise Error, "ACP response exceeded 10 MB" if line.bytesize > 10.megabytes

          message = JSON.parse(line)
          if message["id"] == expected_id && !message.key?("method")
            raise Error, message.dig("error", "message") if message["error"]
            return message.fetch("result")
          end

          handle_incoming(message) { |chunk| yield chunk if block_given? }
        rescue JSON::ParserError => error
          Rails.logger.warn("Ignoring invalid ACP output for agent #{@hosted_agent.id}: #{error.message}")
        end
      end

      def handle_incoming(message)
        case message["method"]
        when "session/update"
          update = message.dig("params", "update") || {}
          if update["sessionUpdate"] == "agent_message_chunk"
            text = update.dig("content", "text")
            yield text if text.present?
          end
        when "session/request_permission"
          respond_to_permission(message)
        else
          respond_method_not_found(message) if message.key?("id")
        end
      end

      def respond_to_permission(message)
        options = message.dig("params", "options") || []
        choice = options.find { |option| option["kind"] == "allow_once" } ||
          options.find { |option| option["kind"] == "reject_once" }
        raise Error, "ACP permission request has no safe response option" unless choice

        write(
          jsonrpc: "2.0",
          id: message.fetch("id"),
          result: { outcome: { outcome: "selected", optionId: choice.fetch("optionId") } }
        )
      end

      def respond_method_not_found(message)
        write(
          jsonrpc: "2.0",
          id: message["id"],
          error: { code: -32_601, message: "Method not found: #{message['method']}" }
        )
      end

      def write(message)
        @stdin.write(JSON.generate(message))
        @stdin.write("\n")
        @stdin.flush
      rescue IOError, Errno::EPIPE => error
        raise Error, "ACP adapter write failed: #{error.message}"
      end
  end
end
