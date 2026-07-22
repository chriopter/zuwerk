module HostedAgents
  class ChatBridge
    class DeliveryError < StandardError; end

    MAX_RESPONSE_LENGTH = 4_000

    def initialize(agent_event, pool: AcpPool)
      @event = agent_event
      @pool = pool
      @hosted_agent = agent_event.recipient.hosted_agent
    end

    def deliver
      response = nil
      working = false
      raise DeliveryError, "Hosted agent runtime is not running" unless @hosted_agent&.running?

      @event.with_lock do
        return if @event.delivered_at?

        response = response_message
        response.update!(body: "", state: :streaming)
      end

      @event.recipient.update!(working_status: true, working_label: "Replying in shared chat", heartbeat_at: Time.current)
      working = true
      body = +""
      @pool.prompt(@hosted_agent, @event.subject.project, prompt_text) do |chunk|
        next if body.length >= MAX_RESPONSE_LENGTH

        body << chunk.to_s.first(MAX_RESPONSE_LENGTH - body.length)
        response.update!(body: body)
      end

      raise DeliveryError, "ACP agent returned an empty response" if body.blank?

      response.update!(state: :completed)
      @event.update!(delivered_at: Time.current, last_error: nil)
    rescue => error
      record_failure(error, response)
      raise error if error.is_a?(DeliveryError)

      raise DeliveryError, "Hosted bridge failed: #{error.message}"
    ensure
      if working
        @event.recipient.update!(working_status: false, working_label: nil, heartbeat_at: nil)
      end
    end

    private
      def record_failure(error, response)
        response&.update!(body: "The agent could not complete this reply.", state: :completed)
        @event.with_lock do
          @event.update!(
            attempts: @event.attempts + 1,
            last_error: "Hosted bridge failed: #{error.class}: #{error.message}".truncate(255)
          )
        end
      rescue => bookkeeping_error
        Rails.logger.error("Hosted event #{@event.id} failure bookkeeping failed: #{bookkeeping_error.message}")
      end

      def response_message
        return @event.response_message if @event.response_message

        message = @event.recipient.messages.create!(
          project: @event.subject.project,
          body: "",
          state: :streaming
        )
        @event.update!(response_message: message)
        message
      end

      def prompt_text
        context = @event.subject.project.messages.where.not(id: @event.response_message_id).includes(:author).order(:created_at).last(20).map do |message|
          "#{message.author.name}: #{message.body}"
        end.join("\n")

        <<~PROMPT
          You are #{@event.recipient.name}, an agent participating in the Zuwerk shared chat for the project #{@event.subject.project.name}.
          A human mentioned you. Reply directly to the latest message in natural language. Be concise and do not prefix the reply with your name.

          Recent shared chat:
          #{context}
        PROMPT
      end
  end
end
