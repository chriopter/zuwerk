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
        @event.event_type == "task_comment_mentioned"
      end

      def briefing_event?
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
            briefing_comment.publish!(body, event: @event)
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
          valid = published == briefing_comment && published&.author == @event.recipient && published.published_at?
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

        <<~PROMPT
          You are #{@event.recipient.name}, an agent connected to Zuwerk through ACP.
          ACP text output is automatically saved as the single correlated project response.
          Do not publish the same final response through the Zuwerk CLI/API.

          Event ID: #{@event.public_id}
          Project ID: #{project.id}
          Project name: #{project.name}
          Triggering message: #{@event.subject.body}

          Acknowledge this event before doing any other work:
          zuwerk events acknowledge #{@event.public_id}

          Read the conversation, including attachment metadata and authenticated download paths, with:
          zuwerk chat list --project #{project.id}

          Search semantically across this project's chat, tasks, comments, and text attachments when earlier context may matter:
          zuwerk search --project #{project.id} --query "<what you need to know>"

          Format the final response with Markdown when useful (bold, italics, lists, links, quotes, and fenced code render in chat). To publish additional file attachments, use the authenticated project chat messages API as multipart form data with `attachments[]`.

          Use the Zuwerk CLI/API only for additional structured project actions. Return the final user-facing answer through ACP.
        PROMPT
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
        <<~PROMPT
          You are #{@event.recipient.name}, the selected agent for a recurring Zuwerk briefing.
          Complete the requested work now and return one polished, self-contained briefing update.
          ACP text output is automatically published as the single correlated Action Text briefing comment.
          Do not publish the same result through the Zuwerk CLI/API or chat.

          Event ID: #{@event.public_id}
          Project ID: #{project.id}
          Project name: #{project.name}
          Briefing: #{briefing.title}
          Scheduled for: #{briefing_comment.scheduled_for.iso8601}

          Acknowledge this event before doing any other work:
          zuwerk events acknowledge #{@event.public_id}

          Recurring prompt:
          #{briefing_comment.prompt_snapshot}

          Refresh project context when needed with:
          zuwerk chat list --project #{project.id}
          zuwerk tasks list --project #{project.id}
          zuwerk search --project #{project.id} --query "<what you need to know>"

          Format the final update with Markdown when useful. Return only the reader-facing briefing comment through ACP.
        PROMPT
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

        <<~PROMPT
          You are #{@event.recipient.name}, an ACP-connected agent working on a specific Zuwerk task.
          ACP text output is automatically saved as the single correlated task comment.
          Do not publish the same final comment through the Zuwerk CLI/API.

          Event ID: #{@event.public_id}
          Trigger: #{reason}
          Project ID: #{project.id}
          Project name: #{project.name}
          Task ID: #{task.id}
          Task title: #{task.title}
          Task status: #{task.status}
          Task ancestry: #{ancestry}
          Task description: #{task.description.to_plain_text.presence || "(none)"}

          Acknowledge this event before doing any other work:
          zuwerk events acknowledge #{@event.public_id}

          Child tasks:
          #{children}

          Existing comments:
          #{comments}

          Refresh the complete task context before acting:
          zuwerk tasks show #{task.id} --project #{project.id}

          Search semantically across this project's chat, tasks, comments, and text attachments when earlier context may matter:
          zuwerk search --project #{project.id} --query "<what you need to know>"

          You may update this task with:
          zuwerk tasks update #{task.id} --project #{project.id} [--title ...] [--description ...] [--status open|completed]

          When this task changes repository files, run the relevant tests and commit the finished changes before reporting the outcome. Never commit credentials or unrelated work. Include the commit hash in the final ACP response. Do not push unless the task explicitly requires it.

          Return the final user-facing outcome through ACP; Zuwerk creates the correlated task comment automatically.
        PROMPT
      end
  end
end
