require "json"
require "timeout"

module AgentConnectors
  class Transport
    class Error < StandardError; end
    class ProtocolError < Error; end
    class Disconnected < Error; end

    MAX_LINE_BYTES = 10.megabytes
    MAX_MESSAGES = 100
    MAX_QUEUE_BYTES = 20.megabytes

    def initialize(max_messages: MAX_MESSAGES, max_queue_bytes: MAX_QUEUE_BYTES, &writer)
      @writer = writer
      @max_messages = max_messages
      @max_queue_bytes = max_queue_bytes
      @queue = []
      @queued_bytes = 0
      @mutex = Mutex.new
      @available = ConditionVariable.new
      @closed = false
    end

    def receive(line)
      validate_line!(line)
      @mutex.synchronize do
        raise Disconnected, "ACP connector disconnected" if @closed
        if @queue.length >= @max_messages || @queued_bytes + line.bytesize > @max_queue_bytes
          close_locked!
          raise ProtocolError, "ACP inbound queue limit exceeded"
        end
        @queue << line
        @queued_bytes += line.bytesize
        @available.signal
      end
    rescue ProtocolError
      disconnect
      raise
    end

    def read_line(timeout: nil)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout
      @mutex.synchronize do
        loop do
          raise Disconnected, "ACP connector disconnected" if @closed
          unless @queue.empty?
            line = @queue.shift
            @queued_bytes -= line.bytesize
            return line
          end
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC) if deadline
          raise Error, "ACP request timed out" if remaining && !remaining.positive?
          @available.wait(@mutex, remaining)
        end
      end
    end

    def queued_messages = @mutex.synchronize { @queue.length }
    def queued_bytes = @mutex.synchronize { @queued_bytes }

    def write_line(line)
      validate_line!(line)
      @mutex.synchronize do
        raise Disconnected, "ACP connector disconnected" if @closed
        @writer.call(line)
      end
    rescue ProtocolError
      disconnect
      raise
    end

    def alive? = !closed?

    def closed?
      @mutex.synchronize { @closed }
    end

    def disconnect
      @mutex.synchronize { close_locked! }
    end

    private
      def close_locked!
        return if @closed
        @closed = true
        @queue.clear
        @queued_bytes = 0
        @available.broadcast
      end

      def validate_line!(line)
        unless line.is_a?(String) && line.end_with?("\n") && line.count("\n") == 1 && line.bytesize <= MAX_LINE_BYTES
          raise ProtocolError, "ACP message must be exactly one bounded NDJSON line"
        end
        parsed = JSON.parse(line)
        raise ProtocolError, "ACP line must contain a JSON object" unless parsed.is_a?(Hash)
      rescue JSON::ParserError
        raise ProtocolError, "ACP line contains malformed JSON"
      end
  end
end
