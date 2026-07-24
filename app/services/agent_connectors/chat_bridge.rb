require "fileutils"

module AgentConnectors
  class ChatBridge
    class DeliveryError < StandardError; end

    MAX_AUTOMATIC_RESPONSE_BYTES = 1.megabyte
    STREAM_FLUSH_INTERVAL = 0.1

    def initialize(agent_event, connection_id:, pool: RemotePool)
      @event = agent_event
      @pool = pool
      @connection_id = connection_id
    end

    def deliver
      @event.reload
      return unless @event.state == "running" && owned_event?

      with_event_lock do
        return if @event.reload.delivered_at?

        perform_delivery
      end
    end

    private
      def perform_delivery
        set_working(true)
        if correlated_publication?
          validate_publication!
          complete_delivery!
          return
        end

        prompt = prompt_text
        return unless store_prompt(prompt)

        chunks = +""
        capture = lambda do |chunk|
          remaining = MAX_AUTOMATIC_RESPONSE_BYTES - chunks.bytesize
          chunks << chunk.to_s.byteslice(0, remaining).to_s.scrub if remaining.positive?
          stream_project_response(chunks)
        end
        ActiveRecord::Base.connection_handler.clear_active_connections!
        @pool.prompt(@event.recipient, origin, prompt, event: @event, expected_connector_owner: @connection_id, &capture)
        ActiveRecord::Base.connection_handler.clear_active_connections!
        unless owned_event?
          discard_streamed_response
          return
        end

        stream_project_response(chunks, force: true)
        publish_automatic_response(chunks)
        validate_publication!
        complete_delivery!
      rescue => error
        discard_streamed_response
        record_failure(error)
        raise error if error.is_a?(DeliveryError)

        raise DeliveryError, "ACP delivery failed: #{error.message}"
      ensure
        set_working(false) if @working
        AgentEvent.schedule_next_for!(@event.recipient) if connector_owns_event? && @event.reload.state.in?(AgentEvent::TERMINAL_STATES)
        ActiveRecord::Base.connection_handler.clear_active_connections!
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
        @event.project
      end

      def task
        @event.subject.task if task_event?
      end

      def briefing_comment
        @event.subject if briefing_event?
      end

      def briefing
        briefing_comment&.briefing
      end

      def origin
        return task if task_event?
        return briefing if briefing_event?

        project
      end

      def task_event?
        @event.event_type.in?(%w[task_assigned task_comment_mentioned])
      end

      def comment_mention_event?
        @event.event_type.in?(%w[briefing_comment_mentioned task_comment_mentioned])
      end

      def briefing_event?
        @event.event_type.in?(%w[briefing_comment_mentioned briefing_scheduled])
      end

      def scheduled_briefing_event?
        @event.event_type == "briefing_scheduled"
      end

      def publish_automatic_response(chunks)
        body = chunks.strip
        return if body.blank?
        mutate_owned_event do
          @event.reload
          next if @event.publication_chat_message || @event.publication_task_comment || @event.publication_briefing_comment&.published_at?

          if task_event?
            task.comments.create!(author: @event.recipient, body: body, agent_event: @event)
          elsif briefing_event?
            if scheduled_briefing_event?
              briefing_comment.publish!(body, event: @event)
            else
              html = Commonmarker.to_html(body, options: { render: { unsafe: false } })
              briefing.comments.create!(author: @event.recipient, body: html, published_at: Time.current, agent_event: @event)
            end
          else
            body = body.truncate(ChatMessage::MAX_BODY_LENGTH, omission: "")
            @event.recipient.chat_messages.create!(chat: project.chat, body: body, agent_event: @event)
          end
        end
      rescue ActiveRecord::RecordNotUnique
        @event.reload
      end

      def stream_project_response(chunks, force: false)
        return if task_event? || briefing_event?
        return if !force && !stream_flush_due?

        body = chunks.strip.truncate(ChatMessage::MAX_BODY_LENGTH, omission: "")
        return if body.blank?

        mutate_owned_event do
          @event.reload
          publication = @streamed_message || @event.publication_chat_message
          if publication
            next unless publication == @streamed_message

            publication.update!(body:) unless publication.body == body
          else
            @streamed_message = @event.recipient.chat_messages.create!(chat: project.chat, body:, agent_event: @event)
          end
          @last_stream_flush_at = monotonic_time
        end
      rescue ActiveRecord::RecordNotUnique
        @event.reload
      end

      def stream_flush_due?
        @last_stream_flush_at.nil? || monotonic_time - @last_stream_flush_at >= STREAM_FLUSH_INTERVAL
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def discard_streamed_response
        message = @streamed_message
        return unless message&.persisted?

        message.destroy!
        @streamed_message = nil
      rescue => cleanup_error
        Rails.logger.error("ACP event #{@event.id} streaming cleanup failed: #{cleanup_error.message}")
      end

      def store_prompt(prompt)
        mutate_owned_event do
          @event.update!(prompt_snapshot: prompt, prompted_at: Time.current)
        end
      end

      def correlated_publication?
        @event.reload
        return @event.publication_task_comment.present? if task_event?
        return @event.publication_briefing_comment&.published_at? if briefing_event?

        @event.publication_chat_message.present?
      end

      def complete_delivery!
        mutate_owned_event do
          @event.update!(delivered_at: Time.current, last_error: nil)
          @event.transition_to!("completed")
        end
      end

      def validate_publication!
        @event.reload
        if task_event?
          published = @event.publication_task_comment
          valid = published&.author == @event.recipient && published.task == task
          raise DeliveryError, "Recipient did not create an event-correlated task comment" unless valid
        elsif briefing_event?
          published = @event.publication_briefing_comment
          valid = published&.author == @event.recipient && published&.briefing == briefing && published.published_at?
          valid &&= published == briefing_comment if scheduled_briefing_event?
          raise DeliveryError, "Recipient did not create an event-correlated briefing comment" unless valid
        else
          published = @event.publication_chat_message
          valid = published&.author == @event.recipient && published.project == project
          raise DeliveryError, "Recipient did not create an event-correlated project message" unless valid
        end
      end

      def set_working(value)
        return unless value ? owned_event? : connector_owns_event?
        @event.recipient.update!(
          working_status: value,
          working_label: value ? working_label : nil,
          heartbeat_at: value ? Time.current : nil
        )
        @working = value
      end

      def record_failure(error)
        mutate_owned_event do
          attributes = {
            attempts: @event.attempts + 1,
            last_error: "ACP delivery failed: #{error.class}: #{error.message}".truncate(255)
          }
          @event.update!(attributes)
        end
      rescue => bookkeeping_error
        Rails.logger.error("ACP event #{@event.id} failure bookkeeping failed: #{bookkeeping_error.message}")
      end

      def owned_event?
        AgentEvent.where(id: @event.id, state: %w[running waiting_for_approval], connector_connection_id: @connection_id).exists?
      end

      def connector_owns_event?
        AgentEvent.where(id: @event.id, connector_connection_id: @connection_id).exists?
      end

      def mutate_owned_event
        changed = false
        @event.with_lock do
          @event.reload
          if @event.state.in?(%w[running waiting_for_approval]) && @event.connector_connection_id == @connection_id
            yield
            changed = true
          end
        end
        changed
      end

      def prompt_text
        return task_prompt_text if task_event?
        return briefing_prompt_text if briefing_event?

        PromptTemplates.render(:chat, {
          agent_name: @event.recipient.name,
          event_id: @event.public_id,
          project_id: project.id,
          project_name: project.name,
          triggering_message: @event.subject.body
        })
      end


      def working_label
        label = if task_event?
          "Working on #{task.title}"
        elsif briefing_event?
          "Updating #{briefing.title}"
        else
          "Replying in shared chat"
        end
        label.truncate(80)
      end

      def briefing_prompt_text
        return briefing_mention_prompt_text if comment_mention_event?

        PromptTemplates.render(:briefing_scheduled, {
          agent_name: @event.recipient.name,
          event_id: @event.public_id,
          project_id: project.id,
          project_name: project.name,
          briefing_title: briefing.title,
          scheduled_for: briefing_comment.scheduled_for.iso8601,
          recurring_prompt: briefing_comment.prompt_snapshot
        })
      end

      def briefing_mention_prompt_text
        comments = briefing.comments.published.includes(:author, :rich_text_body).chronologically.map do |comment|
          "- #{comment.author.name} (#{comment.published_at.iso8601}): #{comment.body.to_plain_text}"
        end.join("\n").presence || "(none)"

        PromptTemplates.render(:briefing_mention, {
          agent_name: @event.recipient.name,
          event_id: @event.public_id,
          project_id: project.id,
          project_name: project.name,
          briefing_title: briefing.title,
          recurring_prompt: briefing.prompt.to_plain_text,
          comment_reference: "##{briefing_comment.id}",
          comment_body: briefing_comment.body.to_plain_text,
          existing_updates: comments
        })
      end

      def task_prompt_text
        ancestry = task.ancestors.map(&:title).join(" > ").presence || "(top level)"
        children = task.children.ordered.map { |child| "- [#{child.status}] ##{child.id} #{child.title}" }.join("\n").presence || "(none)"
        comments = task.comments.includes(:author, :rich_text_body).order(:created_at).map do |comment|
          "- #{comment.author.name} (#{comment.created_at.iso8601}): #{comment.body.to_plain_text}"
        end.join("\n").presence || "(none)"
        reason = if comment_mention_event?
          "You were mentioned in comment ##{@event.subject.id}: #{@event.subject.body.to_plain_text}"
        else
          "You were assigned to this task."
        end

        PromptTemplates.render(:task, {
          agent_name: @event.recipient.name,
          event_id: @event.public_id,
          trigger: reason,
          project_id: project.id,
          project_name: project.name,
          task_id: task.id,
          task_title: task.title,
          task_status: task.status,
          task_ancestry: ancestry,
          task_description: task.description.to_plain_text.presence || "(none)",
          child_tasks: children,
          existing_comments: comments
        })
      end
  end
end
