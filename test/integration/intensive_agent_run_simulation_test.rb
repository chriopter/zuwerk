require "test_helper"

class IntensiveAgentRunSimulationTest < ActionDispatch::IntegrationTest
  class DeterministicAcpPool
    attr_reader :attempts, :claims, :approval_option_ids, :snapshots

    def initialize(human:, event_numbers:, seed:)
      @human = human
      @event_numbers = event_numbers
      @seed = seed
      @attempts = Hash.new(0)
      @claims = Hash.new { |hash, key| hash[key] = [] }
      @approval_option_ids = []
      @snapshots = Hash.new { |hash, key| hash[key] = {} }
    end

    def prompt(agent, origin, _text, event:, expected_connector_owner:)
      raise "stale connector owner" unless event.reload.connector_connection_id == expected_connector_owner
      number = @event_numbers.fetch(event.id)
      runtime = agent.name
      @attempts[event.id] += 1
      @claims[agent.id] << event.id
      capture(runtime, :running, event, origin)

      process_approval(event, runtime, number, origin) if approval_plan.key?(number) && event.agent_approvals.none?

      # Deterministic transport failures exercise retry without creating a second event.
      if transient_failure_numbers.include?(number) && @attempts[event.id] == 1
        raise AgentConnectors::ChatBridge::DeliveryError, "deterministic ACP transport interruption"
      end

      publish(event, origin, number)
      yield "ignored ACP chunk #{number}" if block_given?
      { "stopReason" => "end_turn", "seed" => @seed }
    end

    private
      def approval_plan
        {
          0 => [ "allow-string", "allow_once" ],
          1 => [ 17, "allow_once" ],
          2 => [ { "scope" => "project", "level" => 2 }, "allow_once" ],
          3 => [ nil, "reject_once" ],
          25 => [ "reject-string", "reject_once" ],
          26 => [ 0, "reject_once" ],
          27 => [ { "decision" => "reject" }, "reject_once" ]
        }
      end

      def transient_failure_numbers = [ 3, 18, 41, 64 ]

      def process_approval(event, runtime, number, origin)
        option_id, kind = approval_plan.fetch(number)
        approval = event.agent_approvals.create!(
          request_id: "#{runtime.downcase}-permission-#{number}",
          details: { "title" => "Deterministic #{kind}", "runtime" => runtime },
          options: [ { "optionId" => option_id, "name" => kind.humanize, "kind" => kind } ]
        )
        capture(runtime, :waiting_for_approval, event, origin)
        approval.resolve!(option_id, resolver: @human)
        @approval_option_ids << [ number, approval.reload.selected_option_id ]
        capture(runtime, :resumed, event, origin)
      end

      def publish(event, origin, number)
        if event.event_type == "todo_assigned"
          origin.comments.create!(author: event.recipient, agent_event: event, body: "Completed deterministic run #{number}")
        else
          origin.messages.create!(author: event.recipient, agent_event: event, body: "Completed deterministic run #{number}")
        end
      end

      def capture(runtime, state, event, origin)
        partial = event.event_type == "todo_assigned" ? "agent_events/todo_status" : "agent_events/project_status"
        local = event.event_type == "todo_assigned" ? { todo: origin } : { project: origin }
        @snapshots[runtime][state] = ApplicationController.render(partial:, locals: local)
      end
  end

  [ 77, 101, 202, 303, 404 ].each do |simulation_seed|
    test "completes 77 deterministic user-visible ACP runs across seven projects and three runtimes with seed #{simulation_seed}" do
      result = run_simulation(seed: simulation_seed)

      assert_equal 7, result.fetch(:projects)
      assert_equal 70, result.fetch(:todos)
      assert_equal 7, result.fetch(:trigger_chats)
      assert_equal 77, result.fetch(:events)
      assert_equal 77, result.fetch(:publications)
      assert_equal 77, result.fetch(:completed_events)
      assert_equal 0, result.fetch(:duplicate_correlations)
      assert_equal 0, result.fetch(:pending_approvals)
      assert_equal 0, result.fetch(:nonterminal_events)
      assert_equal [ "Hermes", "Claude", "Codex" ], result.fetch(:runtimes)
      assert_equal({ "Hermes" => 26, "Claude" => 26, "Codex" => 25 }, result.fetch(:runtime_counts))
      assert_equal [ "allow-string", 17, { "scope" => "project", "level" => 2 }, nil,
        "reject-string", 0, { "decision" => "reject" } ], result.fetch(:approval_option_ids)
      assert_equal 4, result.fetch(:retried_events)
      assert result.fetch(:fifo_claims)

      result.fetch(:status_snapshots).each do |runtime, states|
        assert_includes states.fetch(:running), "agent-turn-spinner", "#{runtime} running status"
        assert_not_includes states.fetch(:waiting_for_approval), "agent-turn-spinner", "#{runtime} approval status"
        assert_includes states.fetch(:waiting_for_approval), "Waiting for approval", "#{runtime} approval status"
        assert_includes states.fetch(:resumed), "agent-turn-spinner", "#{runtime} resumed status"
        assert_not_includes states.fetch(:completed), "data-agent-event-id", "#{runtime} completed status"
      end
    end
  end

  private
    def run_simulation(seed:)
      baseline = {
        projects: Project.count,
        todos: Todo.count,
        messages: Message.count,
        events: AgentEvent.count,
        comments: TodoComment.count
      }
      human = User.create!(name: "Simulation Human", email: "simulation-#{seed}@example.com", password: "password1")
      agents = %w[Hermes Claude Codex].map { |runtime| User.create!(name: runtime, kind: :agent) }
      events = []

      7.times do |project_index|
        project = Project.create!(name: "Simulation #{seed}-#{project_index + 1}")
        10.times do |todo_index|
          todo = project.todos.create!(creator: human, title: "Run #{project_index + 1}.#{todo_index + 1}")
          agent = agents[events.length % agents.length]
          assignment = todo.assignments.create!(agent:, assigner: human)
          events << assignment.agent_events.sole
        end
        agent = agents[events.length % agents.length]
        message = project.messages.create!(author: human, body: "@#{agent.handle} run project chat #{project_index + 1}")
        events << message.agent_events.sole
      end

      assert_equal 77, events.length
      event_numbers = events.each_with_index.to_h { |event, number| [ event.id, number ] }
      agents.each do |agent|
        agent.update_columns(
          connector_connection_id: "simulation-#{agent.id}",
          connector_heartbeat_at: Time.current
        )
      end

      pool = DeterministicAcpPool.new(human:, event_numbers:, seed:)
      agents.each do |agent|
        agent_events = events.select { |event| event.recipient_id == agent.id }
        agent_events.each do |event|
          assert_equal event, AgentEvent.where(recipient: agent, state: %w[running queued]).order(:created_at, :id).first
          connection_id = "simulation-#{agent.id}"
          assert_equal event, AgentEvent.claim_for_connector!(agent.id, connection_id)
          bridge = AgentConnectors::ChatBridge.new(event, connection_id:, pool:)
          begin
            bridge.deliver
          rescue AgentConnectors::ChatBridge::DeliveryError => error
            assert_equal "deterministic ACP transport interruption", error.message
            assert_equal "running", event.reload.state
            bridge.deliver
          end
          assert_equal "completed", event.reload.state
          assert event.delivered_at?
        end
      end

      completed_snapshots = {}
      agents.each do |agent|
        event = events.reverse.find { |candidate| candidate.recipient_id == agent.id }
        origin = event.event_type == "todo_assigned" ? event.todo : event.project
        partial = event.event_type == "todo_assigned" ? "agent_events/todo_status" : "agent_events/project_status"
        local = event.event_type == "todo_assigned" ? { todo: origin } : { project: origin }
        pool.snapshots[agent.name][:completed] = ApplicationController.render(partial:, locals: local)
        completed_snapshots[agent.name] = pool.snapshots.fetch(agent.name)
      end

      publication_ids = events.map do |event|
        publication = event.publication_message || event.publication_comment
        assert publication, "event #{event.public_id} must have one correlated publication"
        [ publication.class.name, publication.id ]
      end
      {
        projects: Project.count - baseline[:projects],
        todos: Todo.count - baseline[:todos],
        trigger_chats: Message.where(author: human).count,
        events: AgentEvent.count - baseline[:events],
        publications: (Message.count - baseline[:messages] - 7) + (TodoComment.count - baseline[:comments]),
        completed_events: events.count { |event| event.reload.state == "completed" },
        duplicate_correlations: publication_ids.length - publication_ids.uniq.length,
        pending_approvals: AgentApproval.where(agent_event: events, state: "pending").count,
        nonterminal_events: AgentEvent.where(id: events, state: %w[queued running waiting_for_approval]).count,
        runtimes: agents.map(&:name),
        runtime_counts: events.group_by { |event| event.recipient.name }.transform_values(&:count),
        approval_option_ids: pool.approval_option_ids.sort_by(&:first).map(&:last),
        retried_events: pool.attempts.count { |_id, attempts| attempts == 2 },
        fifo_claims: agents.all? do |agent|
          pool.claims.fetch(agent.id) == events.select { |event| event.recipient_id == agent.id }.flat_map do |event|
            [ event.id ] * pool.attempts.fetch(event.id)
          end
        end,
        status_snapshots: completed_snapshots
      }
    end
end
