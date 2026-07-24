module AgentConnectors
  class PromptTemplates
    Template = Data.define(:name, :description, :body)
    Type = Data.define(:id, :name, :description)

    MASTER_BODY = <<~PROMPT.freeze
      You are {{agent_name}}, an agent connected to Zuwerk through ACP.
      Work type: {{work_type}}

      {{delivery_instructions}}

      Event ID: {{event_id}}
      Project ID: {{project_id}}
      Project name: {{project_name}}

      {{work_context}}

      Acknowledge this event before doing any other work:
      zuwerk events acknowledge {{event_id}}

      {{context_instructions}}

      {{action_instructions}}

      {{response_instructions}}
    PROMPT

    TYPE_CONFIGS = {
      chat: {
        name: "Chat mention",
        description: "An agent is mentioned in a project's shared chat.",
        delivery_instructions: <<~TEXT,
          ACP text output is automatically saved as the single correlated project response.
          Do not publish the same final response through the Zuwerk CLI/API.
        TEXT
        work_context: "Triggering message: {{triggering_message}}",
        context_instructions: <<~TEXT,
          Read the conversation, including attachment metadata and authenticated download paths, with:
          zuwerk chat list --project {{project_id}}

          Search semantically across this project's chat, tasks, comments, and text attachments when earlier context may matter:
          zuwerk search --project {{project_id}} --query "<what you need to know>"
        TEXT
        action_instructions: "Use the Zuwerk CLI/API only for additional structured project actions.",
        response_instructions: "Format the final response with Markdown when useful. Return the final user-facing answer through ACP."
      },
      task: {
        name: "Task",
        description: "An agent is assigned to a task or mentioned in a task comment.",
        delivery_instructions: <<~TEXT,
          ACP text output is automatically saved as the single correlated task comment.
          Do not publish the same final comment through the Zuwerk CLI/API.
        TEXT
        work_context: <<~TEXT,
          Trigger: {{trigger}}
          Task ID: {{task_id}}
          Task title: {{task_title}}
          Task status: {{task_status}}
          Task ancestry: {{task_ancestry}}
          Task description: {{task_description}}

          Child tasks:
          {{child_tasks}}

          Existing comments:
          {{existing_comments}}
        TEXT
        context_instructions: <<~TEXT,
          Refresh the complete task context before acting:
          zuwerk tasks show {{task_id}} --project {{project_id}}

          Search semantically across this project's chat, tasks, comments, and text attachments when earlier context may matter:
          zuwerk search --project {{project_id}} --query "<what you need to know>"
        TEXT
        action_instructions: <<~TEXT,
          You may update this task with:
          zuwerk tasks update {{task_id}} --project {{project_id}} [--title ...] [--description ...] [--status open|completed]

          When this task changes repository files, run the relevant tests and commit the finished changes before reporting the outcome. Never commit credentials or unrelated work. Include the commit hash in the final ACP response. Do not push unless the task explicitly requires it.
        TEXT
        response_instructions: "Return the final user-facing outcome through ACP; Zuwerk creates the correlated task comment automatically."
      },
      briefing_scheduled: {
        name: "Scheduled briefing",
        description: "A recurring or manually triggered briefing run is due.",
        delivery_instructions: <<~TEXT,
          Complete the requested work now and return one polished, self-contained briefing update.
          ACP text output is automatically published as the single correlated Action Text briefing comment.
          Do not publish the same result through the Zuwerk CLI/API or chat.
        TEXT
        work_context: <<~TEXT,
          Briefing: {{briefing_title}}
          Scheduled for: {{scheduled_for}}

          Recurring prompt:
          {{recurring_prompt}}
        TEXT
        context_instructions: <<~TEXT,
          Refresh project context when needed with:
          zuwerk chat list --project {{project_id}}
          zuwerk tasks list --project {{project_id}}
          zuwerk search --project {{project_id}} --query "<what you need to know>"
        TEXT
        action_instructions: "Use the Zuwerk CLI/API only for additional structured project actions.",
        response_instructions: "Format the final update with Markdown when useful. Return only the reader-facing briefing comment through ACP."
      },
      briefing_mention: {
        name: "Briefing mention",
        description: "An agent is mentioned in the discussion below a briefing.",
        delivery_instructions: <<~TEXT,
          ACP text output is automatically saved as the single correlated briefing comment.
          Do not publish the same final comment through the Zuwerk CLI/API or chat.
        TEXT
        work_context: <<~TEXT,
          Briefing: {{briefing_title}}
          Recurring prompt: {{recurring_prompt}}
          Trigger: You were mentioned in comment {{comment_reference}}: {{comment_body}}

          Existing briefing updates:
          {{existing_updates}}
        TEXT
        context_instructions: <<~TEXT,
          Refresh project context when needed with:
          zuwerk chat list --project {{project_id}}
          zuwerk tasks list --project {{project_id}}
          zuwerk search --project {{project_id}} --query "<what you need to know>"
        TEXT
        action_instructions: "Use the Zuwerk CLI/API only for additional structured project actions.",
        response_instructions: "Format the final response with Markdown when useful. Return only the reader-facing briefing comment through ACP."
      }
    }.freeze

    EXAMPLE_VALUES = {
      chat: {
        triggering_message: "@fable-dev Please research the current options and summarize your recommendation."
      },
      task: {
        trigger: "You were mentioned in comment #42: @fable-dev please finish this task.",
        task_id: 42,
        task_title: "Prepare the launch checklist",
        task_status: "open",
        task_ancestry: "Website launch > Release preparation",
        task_description: "Review the remaining launch risks and complete the checklist.",
        child_tasks: "- [completed] #43 Verify production configuration\n- [open] #44 Confirm release owner",
        existing_comments: "- Ada (2026-07-24T09:15:00Z): The production environment is ready."
      },
      briefing_scheduled: {
        briefing_title: "Weekly product briefing",
        scheduled_for: "2026-07-24T09:00:00Z",
        recurring_prompt: "Summarize progress, risks, decisions, and the three most important next steps."
      },
      briefing_mention: {
        briefing_title: "Weekly product briefing",
        recurring_prompt: "Summarize progress, risks, decisions, and the three most important next steps.",
        comment_reference: "#27",
        comment_body: "@fable-dev Which of these risks needs attention first?",
        existing_updates: "- Fable Dev (2026-07-24T09:00:00Z): The release remains on schedule.\n- Ada (2026-07-24T09:20:00Z): Please clarify the migration risk."
      }
    }.freeze

    COMMON_EXAMPLE_VALUES = {
      agent_name: "Fable Dev",
      event_id: "00000000-0000-4000-8000-000000000001",
      project_id: 1,
      project_name: "Example workspace"
    }.freeze

    class << self
      def master
        Template.new(
          name: "ACP master prompt",
          description: "Every ACP request uses this envelope. The work type supplies the four marked instruction blocks.",
          body: MASTER_BODY
        )
      end

      def types
        TYPE_CONFIGS.map do |id, config|
          Type.new(id: id.to_s, name: config.fetch(:name), description: config.fetch(:description))
        end
      end

      def render(id, values)
        config = TYPE_CONFIGS.fetch(id)
        type_values = config.slice(:delivery_instructions, :work_context, :context_instructions, :action_instructions, :response_instructions)
          .transform_values { |body| interpolate(body, values) }

        interpolate(MASTER_BODY, values.merge(work_type: id, **type_values))
      end

      def previews
        TYPE_CONFIGS.keys.index_with do |id|
          render(id, COMMON_EXAMPLE_VALUES.merge(EXAMPLE_VALUES.fetch(id)))
        end
      end

      private

      def interpolate(body, values)
        body.gsub(/\{\{([a-z_]+)\}\}/) do
          values.fetch(Regexp.last_match(1).to_sym).to_s
        end
      end
    end
  end
end
