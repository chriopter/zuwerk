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
        @pool.prompt(@hosted_agent, origin, prompt_text) { |_chunk| }

        validate_publication!

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

      def todo
        @event.subject.todo if todo_event?
      end

      def origin
        todo_event? ? todo : project
      end

      def todo_event?
        @event.event_type == "todo_assigned"
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
        @event.recipient.update!(
          working_status: value,
          working_label: value ? (todo_event? ? "Working on #{todo.title}" : "Replying in shared chat") : nil,
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
        return todo_prompt_text if todo_event?

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


      def todo_prompt_text
        ancestry = todo.ancestors.map(&:title).join(" > ").presence || "(top level)"
        children = todo.children.ordered.map { |child| "- [#{child.status}] ##{child.id} #{child.title}" }.join("\n").presence || "(none)"
        comments = todo.comments.includes(:author, :rich_text_body).order(:created_at).map do |comment|
          "- #{comment.author.name} (#{comment.created_at.iso8601}): #{comment.body.to_plain_text}"
        end.join("\n").presence || "(none)"

        <<~PROMPT
          You are #{@event.recipient.name}, a hosted agent assigned to a specific Zuwerk todo.
          ACP output is invisible to Zuwerk users. ACP only wakes you; do not answer through ACP output.

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

          When this todo changes repository files, run the relevant tests and commit the finished changes before reporting the outcome. Never commit credentials or unrelated work. Include the commit hash in your todo comment. Do not push unless the todo explicitly requires it.

          Publish the outcome exclusively as an event-correlated todo comment:
          zuwerk todos comments create --project #{project.id} --todo #{todo.id} --event #{@event.public_id} --body "YOUR RESPONSE"

          You must create that todo comment for this turn. There is no automatic ACP response fallback.
        PROMPT
      end
  end
end
