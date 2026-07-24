require "json"

module AgentConnectors
  class AcpClient
    class Error < StandardError; end
    class PermissionCancelled < Error; end
    PERMISSION_CANCELLED = Object.new.freeze

    class PermissionPending < Error
      attr_reader :request_id, :params
      def initialize(request_id, params)
        @request_id, @params = request_id, params
        super("ACP permission requires human approval")
      end
    end

    CLIENT_INFO = { name: "zuwerk", version: "1" }.freeze
    CLIENT_CAPABILITIES = { fs: { readTextFile: true, writeTextFile: true }, terminal: true }.freeze
    attr_reader :agent_capabilities, :session_capabilities

    def initialize(transport:, session_mode: "auto", working_directory: "/workspace")
      @session_mode = session_mode
      @working_directory = working_directory
      @mutex = Mutex.new
      @next_id = 0
      @mode_sessions = {}
      @transport = transport
      initialize_result = request("initialize", { protocolVersion: 2, clientCapabilities: CLIENT_CAPABILITIES, clientInfo: CLIENT_INFO })
      @agent_capabilities = initialize_result.fetch("agentCapabilities", {})
    rescue => error
      close
      raise error if error.is_a?(PermissionPending)
      raise Error, "Could not start ACP adapter: #{error.message}"
    end

    def alive? = @transport&.alive?

    def new_session
      result = request("session/new", { cwd: working_directory, mcpServers: [] })
      session_id = result.fetch("sessionId")
      @session_capabilities = result.except("sessionId")
      apply_session_mode(session_id, @session_capabilities)
      session_id
    end

    def load_session(session_id)
      result = request("session/load", { sessionId: session_id, cwd: working_directory, mcpServers: [] })
      # A resumed session needs the mode reapplied just like a new one, otherwise
      # every ongoing conversation silently keeps the adapter's default.
      @session_capabilities = result.except("sessionId") if result.is_a?(Hash)
      apply_session_mode(session_id, @session_capabilities || {})
      session_id
    end

    def prompt(session_id, text, on_update: nil, on_permission: nil, &on_chunk)
      request("session/prompt", { sessionId: session_id, prompt: [ { type: "text", text: text } ] }, timeout: 300, on_update:, on_permission:, &on_chunk)
    end

    def ping(session_id)
      reapply_session_mode(session_id)
      true
    end

    def cancel(session_id)
      write(jsonrpc: "2.0", method: "session/cancel", params: { sessionId: session_id })
    end

    def close = @transport&.disconnect

    private
      attr_reader :session_mode, :working_directory

      # Adapters advertise session modes in two dialects: newer builds list them
      # under `modes.availableModes` and switch with `session/set_mode`, older
      # ones expose a `mode` config option set with `session/set_config_option`.
      # A mode the adapter does not advertise is left untouched.
      def apply_session_mode(session_id, capabilities)
        if mode_available?(capabilities)
          request("session/set_mode", { sessionId: session_id, modeId: session_mode })
          @mode_sessions[session_id] = :set_mode
        elsif mode_advertised?(capabilities)
          request("session/set_config_option", { sessionId: session_id, configId: "mode", value: session_mode })
          @mode_sessions[session_id] = :config_option
        end
      end

      def reapply_session_mode(session_id)
        case @mode_sessions[session_id]
        when :set_mode
          request("session/set_mode", { sessionId: session_id, modeId: session_mode })
        when :config_option
          request("session/set_config_option", { sessionId: session_id, configId: "mode", value: session_mode })
        end
      end

      def mode_available?(capabilities)
        modes = capabilities["modes"]
        return false unless modes.is_a?(Hash)

        object_list(modes["availableModes"]).any? { |mode| mode["id"] == session_mode }
      end

      def mode_advertised?(capabilities)
        object_list(capabilities["configOptions"]).any? do |option|
          option["id"] == "mode" && object_list(option["options"]).any? { |choice| choice["value"] == session_mode }
        end
      end

      def object_list(value)
        case value
        when Hash then [ value ]
        when Array then value.grep(Hash)
        else []
        end
      end

      def request(method, params = {}, timeout: 30, on_update: nil, on_permission: nil, &on_chunk)
        @mutex.synchronize do
          raise Error, "ACP adapter is not running" unless alive?
          id = (@next_id += 1)
          write(jsonrpc: "2.0", id:, method:, params:)
          read_response(id, timeout:, on_update:, on_permission:, session_id: params[:sessionId] || params["sessionId"], &on_chunk)
        end
      end

      def read_response(expected_id, timeout:, on_update: nil, on_permission: nil, session_id: nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Error, "ACP request timed out" unless remaining.positive?
          line = @transport.read_line(timeout: remaining)
          raise Error, "ACP response exceeded 10 MB" if line.bytesize > 10.megabytes
          message = JSON.parse(line)
          if message["id"] == expected_id && !message.key?("method")
            raise Error, message.dig("error", "message") if message["error"]
            return message.fetch("result")
          end
          handle_incoming(message, on_update:, on_permission:, session_id:) { |chunk| yield chunk if block_given? }
        rescue JSON::ParserError => error
          raise Error, "Invalid ACP output: #{error.message}"
        rescue AgentConnectors::Transport::Error => error
          raise Error, "ACP adapter read failed: #{error.message}"
        rescue PermissionCancelled
          drain_response(expected_id, timeout: 0.25)
          close
          raise Error, "ACP permission was cancelled"
        end
      end

      def handle_incoming(message, on_update: nil, on_permission: nil, session_id: nil)
        case message["method"]
        when "session/update"
          update = message.dig("params", "update") || {}
          on_update&.call(update)
          text = content_text(update["content"])
          yield text if update["sessionUpdate"] == "agent_message_chunk" && text.present?
        when "session/request_permission"
          raise PermissionPending.new(message.fetch("id"), message.fetch("params", {})) unless on_permission
          option_id = on_permission.call(message.fetch("id"), message.fetch("params", {}))
          cancelled = option_id.equal?(PERMISSION_CANCELLED)
          outcome = cancelled ? { outcome: "cancelled" } : { outcome: "selected", optionId: option_id }
          write(jsonrpc: "2.0", id: message.fetch("id"), result: { outcome: outcome })
          if cancelled
            cancel(message.dig("params", "sessionId") || session_id)
            raise PermissionCancelled
          end
        else
          respond_method_not_found(message) if message.key?("id")
        end
      end

      def drain_response(expected_id, timeout:)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break unless remaining.positive?
          message = JSON.parse(@transport.read_line(timeout: remaining))
          break if message["id"] == expected_id && !message.key?("method")
        end
      rescue Error, AgentConnectors::Transport::Error, JSON::ParserError
        nil
      end

      def content_text(content)
        object_list(content).filter_map { |block| block["text"] if block["type"].nil? || block["type"] == "text" }.join
      end

      def respond_method_not_found(message)
        write(jsonrpc: "2.0", id: message["id"], error: { code: -32_601, message: "Method not found: #{message['method']}" })
      end

      def write(message)
        @transport.write_line(JSON.generate(message) + "\n")
      rescue IOError, Errno::EPIPE, AgentConnectors::Transport::Error => error
        raise Error, "ACP adapter write failed: #{error.message}"
      end
  end
end
