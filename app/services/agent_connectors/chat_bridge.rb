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
        return unless mutate_owned_event { @event.acknowledge! }
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
        @event.subject.project
      end

      def todo
        @event.subject.todo if todo_event?
      end

      def board_post
        @event.subject if board_event?
      end

      def board_automation
        board_post&.board_automation
      end

      def origin
        return todo if todo_event?
        return board_automation if board_event?

        project
      end

      def todo_event?
        @event.event_type == "todo_assigned"
      end

      def board_event?
        @event.event_type == "board_scheduled"
      end

      def publish_automatic_response(chunks)
        body = chunks.strip
        return if body.blank?
        mutate_owned_event do
          @event.reload
          next if @event.publication_message || @event.publication_comment || @event.publication_board_post&.published_at?

          if todo_event?
            todo.comments.create!(author: @event.recipient, body: body, agent_event: @event)
          elsif board_event?
            board_post.publish!(body, event: @event)
          else
            body = body.truncate(Message::MAX_BODY_LENGTH, omission: "")
            @event.recipient.messages.create!(project: project, body: body, agent_event: @event)
          end
        end
      rescue ActiveRecord::RecordNotUnique
        @event.reload
      end

      def stream_project_response(chunks, force: false)
        return if todo_event? || board_event?
        return if !force && !stream_flush_due?

        body = chunks.strip.truncate(Message::MAX_BODY_LENGTH, omission: "")
        return if body.blank?

        mutate_owned_event do
          @event.reload
          publication = @streamed_message || @event.publication_message
          if publication
            next unless publication == @streamed_message

            publication.update!(body:) unless publication.body == body
          else
            @streamed_message = @event.recipient.messages.create!(project: project, body:, agent_event: @event)
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
        return @event.publication_comment.present? if todo_event?
        return @event.publication_board_post&.published_at? if board_event?

        @event.publication_message.present?
      end

      def complete_delivery!
        mutate_owned_event do
          @event.update!(delivered_at: Time.current, last_error: nil)
          @event.transition_to!("completed")
        end
      end

      def validate_publication!
        @event.reload
        if todo_event?
          published = @event.publication_comment
          valid = published&.author == @event.recipient && published.todo == todo
          raise DeliveryError, "Recipient did not create an event-correlated todo comment" unless valid
        elsif board_event?
          published = @event.publication_board_post
          valid = published == board_post && published&.author == @event.recipient && published.published_at?
          raise DeliveryError, "Recipient did not create an event-correlated board post" unless valid
        else
          published = @event.publication_message
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
        return todo_prompt_text if todo_event?
        return board_prompt_text if board_event?

        <<~PROMPT
          You are #{@event.recipient.name}, an agent connected to Zuwerk through ACP.
          ACP text output is automatically saved as the single correlated project response.
          Do not publish the same final response through the Zuwerk CLI/API.

          Event ID: #{@event.public_id}
          Project ID: #{project.id}
          Project name: #{project.name}
          Triggering message: #{@event.subject.body}

          Read the conversation, including attachment metadata and authenticated download paths, with:
          zuwerk messages list --project #{project.id}

          Search semantically across this project's chat, tasks, comments, and text attachments when earlier context may matter:
          zuwerk search --project #{project.id} --query "<what you need to know>"

          Format the final response with Markdown when useful (bold, italics, lists, links, quotes, and fenced code render in chat). To publish additional file attachments, use the authenticated project messages API as multipart form data with `attachments[]`.

          Use the Zuwerk CLI/API only for additional structured project actions. Return the final user-facing answer through ACP.
        PROMPT
      end


      def working_label
        label = if todo_event?
          "Working on #{todo.title}"
        elsif board_event?
          "Writing #{board_automation.title}"
        else
          "Replying in shared chat"
        end
        label.truncate(80)
      end

      def board_prompt_text
        <<~PROMPT
          You are #{@event.recipient.name}, the selected agent for a recurring Zuwerk Board publication.
          Complete the requested work now and return one polished, self-contained Board post.
          ACP text output is automatically published as the single correlated Action Text Board post.
          Do not publish the same result through the Zuwerk CLI/API or chat.

          Event ID: #{@event.public_id}
          Project ID: #{project.id}
          Project name: #{project.name}
          Board automation: #{board_automation.title}
          Scheduled for: #{board_post.scheduled_for.iso8601}

          Recurring prompt:
          #{board_post.prompt_snapshot}

          Refresh project context when needed with:
          zuwerk messages list --project #{project.id}
          zuwerk todos list --project #{project.id}
          zuwerk search --project #{project.id} --query "<what you need to know>"

          Format the final publication with Markdown when useful. Return only the reader-facing post through ACP.
        PROMPT
      end

      def todo_prompt_text
        ancestry = todo.ancestors.map(&:title).join(" > ").presence || "(top level)"
        children = todo.children.ordered.map { |child| "- [#{child.status}] ##{child.id} #{child.title}" }.join("\n").presence || "(none)"
        comments = todo.comments.includes(:author, :rich_text_body).order(:created_at).map do |comment|
          "- #{comment.author.name} (#{comment.created_at.iso8601}): #{comment.body.to_plain_text}"
        end.join("\n").presence || "(none)"

        <<~PROMPT
          You are #{@event.recipient.name}, an ACP-connected agent assigned to a specific Zuwerk todo.
          ACP text output is automatically saved as the single correlated todo comment.
          Do not publish the same final comment through the Zuwerk CLI/API.

          Event ID: #{@event.public_id}
          Project ID: #{project.id}
          Project name: #{project.name}
          Todo ID: #{todo.id}
          Todo title: #{todo.title}
          Todo status: #{todo.status}
          Todo ancestry: #{ancestry}
          Todo description: #{todo.description.to_plain_text.presence || "(none)"}

          Child todos:
          #{children}

          Existing comments:
          #{comments}

          Refresh the complete todo context before acting:
          zuwerk todos show #{todo.id} --project #{project.id}

          Search semantically across this project's chat, tasks, comments, and text attachments when earlier context may matter:
          zuwerk search --project #{project.id} --query "<what you need to know>"

          You may update this todo with:
          zuwerk todos update #{todo.id} --project #{project.id} [--title ...] [--description ...] [--status open|completed]

          When this todo changes repository files, run the relevant tests and commit the finished changes before reporting the outcome. Never commit credentials or unrelated work. Include the commit hash in the final ACP response. Do not push unless the todo explicitly requires it.

          Return the final user-facing outcome through ACP; Zuwerk creates the correlated todo comment automatically.
        PROMPT
      end
  end
end
