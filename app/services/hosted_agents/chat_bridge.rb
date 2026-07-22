require "fileutils"

module HostedAgents
  class ChatBridge
    class DeliveryError < StandardError; end

    MAX_AUTOMATIC_RESPONSE_BYTES = 1.megabyte

    def initialize(agent_event, pool: AcpPool, connector: false, expected_connector_owner: nil)
      @event = agent_event
      @pool = pool
      @hosted_agent = agent_event.recipient.hosted_agent
      @connector = connector
      @expected_connector_owner = expected_connector_owner
    end

    def deliver
      @event.reload
      return unless @event.state.in?(%w[queued running])

      claimed = @event.state == "queued" ? AgentEvent.claim_next_for!(@event.recipient) : @event
      return unless claimed == @event

      with_event_lock do
        return if @event.reload.delivered_at?

        perform_delivery
      end
    end

    private
      def perform_delivery
        raise DeliveryError, "Agent runtime is not running" unless @connector || @hosted_agent&.running?

        return unless mutate_owned_event { @event.acknowledge! }
        set_working(true)
        chunks = +""
        capture = lambda do |chunk|
          remaining = MAX_AUTOMATIC_RESPONSE_BYTES - chunks.bytesize
          chunks << chunk.to_s.byteslice(0, remaining).to_s.scrub if remaining.positive?
        end
        prompt_target = @connector ? @event.recipient : @hosted_agent
        prompt_origin = origin
        prompt = prompt_text
        ActiveRecord::Base.connection_handler.clear_active_connections!
        if @connector
          @pool.prompt(prompt_target, prompt_origin, prompt, event: @event, expected_connector_owner: @expected_connector_owner, &capture)
        else
          @pool.prompt(prompt_target, prompt_origin, prompt, &capture)
        end
        ActiveRecord::Base.connection_handler.clear_active_connections!
        return unless owned_event?

        publish_automatic_response(chunks)
        validate_publication!

        mutate_owned_event do
          @event.update!(delivered_at: Time.current, last_error: nil)
          @event.transition_to!("completed")
        end
      rescue => error
        record_failure(error)
        raise error if error.is_a?(DeliveryError)

        raise DeliveryError, "Hosted bridge failed: #{error.message}"
      ensure
        set_working(false) if @working
        AgentEvent.schedule_next_for!(@event.recipient) if owned_event? && @event.reload.state.in?(AgentEvent::TERMINAL_STATES)
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

      def origin
        todo_event? ? todo : project
      end

      def todo_event?
        @event.event_type == "todo_assigned"
      end

      def publish_automatic_response(chunks)
        body = chunks.strip
        return if body.blank?
        mutate_owned_event do
          @event.reload
          next if @event.publication_message || @event.publication_comment

          if todo_event?
            todo.comments.create!(author: @event.recipient, body: body, agent_event: @event)
          else
            body = body.truncate(Message::MAX_BODY_LENGTH, omission: "")
            @event.recipient.messages.create!(project: project, body: body, agent_event: @event)
          end
        end
      rescue ActiveRecord::RecordNotUnique
        @event.reload
      end

      def validate_publication!
        @event.reload
        if todo_event?
          published = @event.publication_comment
          valid = published&.author == @event.recipient && published.todo == todo
          raise DeliveryError, "Recipient did not create an event-correlated todo comment" unless valid
        else
          published = @event.publication_message
          valid = published&.author == @event.recipient && published.project == project
          raise DeliveryError, "Recipient did not create an event-correlated project message" unless valid
        end
      end

      def set_working(value)
        return unless owned_event?
        @event.recipient.update!(
          working_status: value,
          working_label: value ? (todo_event? ? "Working on #{todo.title}" : "Replying in shared chat").truncate(80) : nil,
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
        mutate_owned_event do
          attributes = {
            attempts: @event.attempts + 1,
            last_error: "Hosted bridge failed: #{error.class}: #{error.message}".truncate(255)
          }
          @event.update!(attributes)
        end
      rescue => bookkeeping_error
        Rails.logger.error("Hosted event #{@event.id} failure bookkeeping failed: #{bookkeeping_error.message}")
      end

      def owned_event?
        return true unless @expected_connector_owner

        AgentEvent.where(id: @event.id, state: %w[running waiting_for_approval], connector_connection_id: @expected_connector_owner).exists?
      end

      def mutate_owned_event
        return yield unless @expected_connector_owner

        changed = false
        @event.with_lock do
          @event.reload
          if @event.state.in?(%w[running waiting_for_approval]) && @event.connector_connection_id == @expected_connector_owner
            yield
            changed = true
          end
        end
        changed
      end

      def prompt_text
        return todo_prompt_text if todo_event?

        <<~PROMPT
          You are #{@event.recipient.name}, a hosted agent participating in Zuwerk.
          ACP text output is automatically saved as the single correlated project response.
          Do not publish the same final response through the Zuwerk CLI/API.

          Event ID: #{@event.public_id}
          Project ID: #{project.id}
          Project name: #{project.name}
          Triggering message: #{@event.subject.body}

          Read the conversation with:
          zuwerk messages list --project #{project.id}

          Use the Zuwerk CLI/API only for additional structured project actions. Return the final user-facing answer through ACP.
        PROMPT
      end


      def todo_prompt_text
        ancestry = todo.ancestors.map(&:title).join(" > ").presence || "(top level)"
        children = todo.children.ordered.map { |child| "- [#{child.status}] ##{child.id} #{child.title}" }.join("\n").presence || "(none)"
        comments = todo.comments.includes(:author, :rich_text_body).order(:created_at).map do |comment|
          "- #{comment.author.name} (#{comment.created_at.iso8601}): #{comment.body.to_plain_text}"
        end.join("\n").presence || "(none)"

        <<~PROMPT
          You are #{@event.recipient.name}, a hosted agent assigned to a specific Zuwerk todo.
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

          You may update this todo with:
          zuwerk todos update #{todo.id} --project #{project.id} [--title ...] [--description ...] [--status open|completed]

          When this todo changes repository files, run the relevant tests and commit the finished changes before reporting the outcome. Never commit credentials or unrelated work. Include the commit hash in the final ACP response. Do not push unless the todo explicitly requires it.

          Return the final user-facing outcome through ACP; Zuwerk creates the correlated todo comment automatically.
        PROMPT
      end
  end
end
