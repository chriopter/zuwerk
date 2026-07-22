module HostedAgents
  class EventWatchdog
    STALE_AFTER = 2.minutes
    MAX_ATTEMPTS = 3
    BASE_BACKOFF = 1.minute

    def initialize(
      event,
      clock: -> { Time.current },
      runtime_factory: ->(hosted_agent) { ContainerRuntime.new(hosted_agent) },
      enqueue: ->(agent_event) { DeliverAgentEventJob.perform_later(agent_event) }
    )
      @event = event
      @clock = clock
      @runtime_factory = runtime_factory
      @enqueue = enqueue
    end

    def call
      @event.with_lock do
        @event.reload
        return @event.state.to_sym if @event.state.in?(AgentEvent::TERMINAL_STATES)
        return complete_from_delivery if @event.delivered_at?
        return complete_from_publication if correlated_publication?
        return :running if running?
        return :waiting unless stale? && retry_due?
        return exhaust! if @event.watchdog_attempts >= MAX_ATTEMPTS

        recover_runtime_once!
        schedule_retry!
      end
    end

    private
      def now = @clock.call

      def hosted_agent = @event.recipient.hosted_agent

      def running?
        @event.accepted_at? && @event.recipient.working_status? &&
          @event.recipient.heartbeat_at.present? && @event.recipient.heartbeat_at > STALE_AFTER.ago(now)
      end

      def stale?
        activity_at = [ @event.accepted_at, @event.updated_at, @event.created_at ].compact.max
        activity_at <= STALE_AFTER.ago(now)
      end

      def retry_due?
        @event.watchdog_retry_at.nil? || @event.watchdog_retry_at <= now
      end

      def correlated_publication?
        publication = @event.event_type == "todo_assigned" ? @event.publication_comment : @event.publication_message
        return false unless publication&.author_id == @event.recipient_id

        if @event.event_type == "todo_assigned"
          publication.todo_id == @event.todo.id
        else
          publication.project_id == @event.subject.project_id
        end
      end

      def complete_from_publication
        @event.update!(delivered_at: now, last_error: nil, watchdog_retry_at: nil, state: "completed", finished_at: now)
        clear_working!
        schedule_next
        :completed
      end

      def complete_from_delivery
        @event.update!(state: "completed", finished_at: now) unless @event.state == "completed"
        clear_working!
        schedule_next
        :completed
      end

      def recover_runtime_once!
        return if @event.runtime_recovered_at?

        runtime = @runtime_factory.call(hosted_agent)
        return if hosted_agent.running? && runtime.running?

        @event.update!(runtime_recovered_at: now)
        runtime.provision
      end

      def schedule_retry!
        attempt = @event.watchdog_attempts + 1
        @event.update!(
          watchdog_attempts: attempt,
          watchdog_retry_at: now + BASE_BACKOFF * (2**(attempt - 1)),
          last_error: nil
        )
        clear_working!
        AcpPool.discard(hosted_agent.id) unless hosted_agent.bridge_connected?
        @enqueue.call(@event)
        :retried
      end

      def exhaust!
        @event.update!(
          last_error: "Agent watchdog retry limit reached after #{MAX_ATTEMPTS} attempts",
          watchdog_retry_at: nil,
          state: "failed",
          finished_at: now
        )
        clear_working!
        schedule_next
        :failed
      end

      def clear_working!
        return unless @event.recipient.working_status? || @event.recipient.heartbeat_at? || @event.recipient.working_label?

        @event.recipient.update!(working_status: false, working_label: nil, heartbeat_at: nil)
      end

      def schedule_next
        next_event = AgentEvent.where(recipient: @event.recipient, state: "queued").order(:created_at, :id).first
        @enqueue.call(next_event) if next_event
      end
  end
end
