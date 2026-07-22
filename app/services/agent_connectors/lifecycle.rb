module AgentConnectors
  class Lifecycle
    POLL_INTERVAL = 0.25
    MAX_ATTEMPTS = 3

    def initialize(agent_id:, connection_id:, transport:, dispatcher_factory: nil, poll_interval: POLL_INTERVAL, before_dispatch: -> { })
      @agent_id = agent_id
      @connection_id = connection_id
      @transport = transport
      @dispatcher_factory = dispatcher_factory || ->(event) { Dispatcher.new(event, connection_id: @connection_id) }
      @poll_interval = poll_interval
      @before_dispatch = before_dispatch
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @stopped = false
    end

    def start
      @thread = Thread.new { run }
      self
    end

    def stop
      @mutex.synchronize do
        @stopped = true
        @condition.broadcast
      end
      @thread&.join(2)
      self
    end

    def drain_once
      return false unless local_owner?

      event = database_operation { AgentEvent.claim_for_connector!(@agent_id, @connection_id) }
      return false unless event
      @current_event_id = event.id

      @before_dispatch.call
      return false unless local_owner? && database_operation { dispatch_owned?(event) }

      @dispatcher_factory.call(event).deliver
      true
    end

    private
      def run
        loop do
          break if stopped?
          drain_once
          wait
        rescue HostedAgents::ChatBridge::DeliveryError => error
          terminal = handle_delivery_error(error, @current_event_id)
          wait(terminal ? @poll_interval : retry_delay)
        rescue => error
          Rails.logger.error("Agent connector lifecycle #{@agent_id} failed: #{error.class}: #{error.message}")
          wait
        end
      ensure
        ActiveRecord::Base.connection_handler.clear_active_connections!
      end

      def local_owner?
        !stopped? && @transport.alive? && AgentConnectors.registry.fetch(@agent_id)&.equal?(@transport)
      end

      def database_operation
        result = nil
        Rails.application.executor.wrap do
          ActiveRecord::Base.connection_pool.with_connection { result = yield }
        end
        result
      end

      def dispatch_owned?(event)
        User.find(@agent_id).heartbeat_connector!(@connection_id) &&
          AgentEvent.where(id: event.id, state: "running", connector_connection_id: @connection_id).exists?
      end

      def handle_delivery_error(error, event_id)
        ActiveRecord::Base.connection_pool.with_connection do
          event = AgentEvent.find_by(id: event_id, state: "running", connector_connection_id: @connection_id)
          terminal = event&.attempts.to_i >= MAX_ATTEMPTS
          event&.terminalize_failure!(error, expected_connector_owner: @connection_id) if terminal
          terminal
        end
      end

      def stopped? = @mutex.synchronize { @stopped }

      def retry_delay
        ActiveRecord::Base.connection_pool.with_connection do
          attempts = AgentEvent.where(id: @current_event_id, state: "running", connector_connection_id: @connection_id).pick(:attempts).to_i
          [ attempts**4 + 2, 30 ].min
        end
      end

      def wait(interval = @poll_interval)
        @mutex.synchronize { @condition.wait(@mutex, interval) unless @stopped }
      end
  end
end
