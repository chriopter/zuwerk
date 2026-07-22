require "application_system_test_case"
require "timeout"

class AgentTodoWorkTest < ApplicationSystemTestCase
  class ControlledCodexPool
    attr_reader :started

    def initialize(agent:, todo:, event:)
      @agent = agent
      @todo = todo
      @event = event
      @started = Queue.new
      @continue = Queue.new
    end

    def prompt(_hosted_agent, origin, _prompt)
      raise "wrong work origin" unless origin == @todo

      @started << true
      @continue.pop
      @todo.comments.create!(author: @agent, body: "Codex finished the browser task", agent_event: @event)
    end

    def finish = @continue << true
  end

  class RecoveredRuntime
    attr_reader :provisioned

    def running? = false

    def provision
      @provisioned = true
    end
  end

  setup do
    @human = User.create!(name: "Browser Human", email: "browser-human@example.com", password: "password1")
    @agent = User.create!(name: "Codex Browser", kind: :agent)
    @hosted_agent = HostedAgent.create!(user: @agent, runtime: "codex", state: "running")
    @project = Project.create!(name: "Browser acceptance")
    @todo = @project.todos.create!(creator: @human, title: "Verify agent feedback")

    visit new_session_path
    fill_in "Email", with: @human.email
    fill_in "Password", with: "password1"
    click_button "Sign in"
    assert_current_path root_path
  end

  test "human toggles an emoji and watches real agent work through completion" do
    comment = @todo.comments.create!(author: @human, body: "Please verify this")
    visit project_todo_path(@project, @todo)

    within "#todo_comment_#{comment.id}" do
      click_button "React with ❤️"
      assert_selector "button.reaction-chip-active", text: /1/
      find("button.reaction-chip-active").click
      assert_no_selector "button.reaction-chip-active"
      assert_no_selector "button.reaction-chip", text: /1/
    end

    assignment = @todo.assignments.create!(agent: @agent, assigner: @human)
    event = assignment.agent_events.find_by!(recipient: @agent)
    pool = ControlledCodexPool.new(agent: @agent, todo: @todo, event: event)
    worker = Thread.new { HostedAgents::ChatBridge.new(event, pool: pool).deliver }
    Timeout.timeout(5) { pool.started.pop }

    visit project_todo_path(@project, @todo)
    assert_text "👍 Codex Browser"
    within "[data-agent-event-id='#{event.public_id}']" do
      assert_text @todo.title
      assert_selector ".sr-only", text: "In progress", visible: :all
      assert_selector ".agent-work-spinner", visible: :all
    end

    pool.finish
    worker.value
    visit project_todo_path(@project, @todo)

    assert_text "Codex finished the browser task"
    assert_no_selector "[data-agent-event-id='#{event.public_id}']"
    assert event.reload.delivered_at?
    assert_not @agent.reload.working?
  ensure
    pool&.finish if worker&.alive?
    worker&.join
  end

  test "watchdog recovers stale work and the awakened agent completes it" do
    assignment = @todo.assignments.create!(agent: @agent, assigner: @human)
    event = assignment.agent_events.find_by!(recipient: @agent)
    event.acknowledge!
    stale_time = 10.minutes.ago
    @agent.update!(working_status: true, working_label: "Working on #{@todo.title}", heartbeat_at: stale_time)
    event.update_columns(accepted_at: stale_time, created_at: stale_time, updated_at: stale_time)
    @hosted_agent.update!(state: "stopped")
    runtime = RecoveredRuntime.new
    retried = []

    result = HostedAgents::EventWatchdog.new(
      event,
      runtime_factory: ->(_hosted) { runtime },
      enqueue: ->(retried_event) { retried << retried_event }
    ).call

    assert_equal :retried, result
    assert runtime.provisioned
    assert_equal [ event ], retried
    assert_equal 1, event.reload.watchdog_attempts
    assert_not @agent.reload.working?

    @hosted_agent.update!(state: "running")
    pool = ControlledCodexPool.new(agent: @agent, todo: @todo, event: event)
    worker = Thread.new { HostedAgents::ChatBridge.new(event, pool: pool).deliver }
    Timeout.timeout(5) { pool.started.pop }
    visit project_todo_path(@project, @todo)
    within "[data-agent-event-id='#{event.public_id}']" do
      assert_selector ".sr-only", text: "In progress", visible: :all
      assert_selector ".agent-work-spinner", visible: :all
    end

    pool.finish
    worker.value
    visit project_todo_path(@project, @todo)

    assert_text "Codex finished the browser task"
    assert_no_selector "[data-agent-event-id='#{event.public_id}']"
    assert event.reload.delivered_at?
    assert_nil event.last_error
  ensure
    pool&.finish if worker&.alive?
    worker&.join
  end
end
