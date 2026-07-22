require "fileutils"

module HostedAgents
  class ChatBridge
    class DeliveryError < StandardError; end

    def initialize(agent_event, pool: AcpPool)
      @event = agent_event
      @pool = pool
      @hosted_agent = agent_event.recipient.hosted_agent
    end

    def deliver
      with_event_lock do
        return if @event.reload.delivered_at?

        perform_delivery
      end
    end

    private
      def perform_delivery
        raise DeliveryError, "Hosted agent runtime is not running" unless @hosted_agent&.running?

        set_working(true)
        @pool.prompt(@hosted_agent, project, prompt_text) { |_chunk| }

        published = @event.reload.publication_message
        unless published&.author == @event.recipient && published.project == project
          raise DeliveryError, "Recipient did not create an event-correlated project message"
        end

        @event.update!(delivered_at: Time.current, last_error: nil)
      rescue => error
        record_failure(error)
        raise error if error.is_a?(DeliveryError)

        raise DeliveryError, "Hosted bridge failed: #{error.message}"
      ensure
        set_working(false) if @working
      end

      def with_event_lock
        directory = Rails.root.join("tmp", "agent-event-locks")
        FileUtils.mkdir_p(directory, mode: 0o700)
        File.open(directory.join("event-#{Integer(@event.id)}.lock"), File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          yield
        ensure
          file.flock(File::LOCK_UN) rescue nil
        end
      end

      def project
        @event.subject.project
      end

      def set_working(value)
        @event.recipient.update!(
          working_status: value,
          working_label: value ? "Replying in shared chat" : nil,
          heartbeat_at: value ? Time.current : nil
        )
        @working = value
      end

      def record_failure(error)
        @hosted_agent&.update_columns(
          bridge_connected_at: nil,
          bridge_last_error: error.message.to_s.truncate(500),
          updated_at: Time.current
        )
        @event.with_lock do
          @event.update!(
            attempts: @event.attempts + 1,
            last_error: "Hosted bridge failed: #{error.class}: #{error.message}".truncate(255)
          )
        end
      rescue => bookkeeping_error
        Rails.logger.error("Hosted event #{@event.id} failure bookkeeping failed: #{bookkeeping_error.message}")
      end

      def prompt_text
        <<~PROMPT
          You are #{@event.recipient.name}, a hosted agent participating in Zuwerk.
          ACP output is invisible to Zuwerk users. ACP only wakes you; do not answer through ACP output.

          Event ID: #{@event.public_id}
          Project ID: #{project.id}
          Project name: #{project.name}
          Triggering message: #{@event.subject.body}

          Read the conversation with:
          zuwerk messages list --project #{project.id}

          Publish your response exclusively through the Zuwerk CLI/API with:
          zuwerk messages create --project #{project.id} --event #{@event.public_id} --body "YOUR RESPONSE"

          You must create a project message for this turn. There is no automatic ACP response fallback.
        PROMPT
      end
  end
end
