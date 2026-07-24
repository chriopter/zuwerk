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

    def prompt(_agent, origin, _prompt, **)
      raise "wrong work origin" unless origin == @todo

      @event.acknowledge!
      @started << true
      @continue.pop
      @todo.comments.create!(author: @agent, body: "Codex finished the browser task", agent_event: @event)
    end

    def finish = @continue << true
  end

  setup do
    @human = User.create!(name: "Browser Human", email: "browser-human@example.com", password: "password1")
    @agent = User.create!(name: "Codex Browser", kind: :agent)
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
      find(".boost-picker > summary").click
      click_button "React with ❤️"
      assert_selector "button.boost-chip.is-own"
      find("button.boost-chip.is-own").click
      assert_no_selector "button.boost-chip"
    end

    assignment = @todo.assignments.create!(agent: @agent, assigner: @human)
    event = assignment.agent_events.find_by!(recipient: @agent)
    event.transition_to!("running")
    event.update_columns(connector_connection_id: "browser-connector")
    pool = ControlledCodexPool.new(agent: @agent, todo: @todo, event: event)
    worker = Thread.new { AgentConnectors::ChatBridge.new(event, connection_id: "browser-connector", pool:).deliver }
    Timeout.timeout(5) { pool.started.pop }

    visit project_todo_path(@project, @todo)
    assert_selector "#todo_reactions .boost-chip[title*='Codex Browser'] .boost-chip-emoji", text: "👍"
    assert_selector "[data-agent-event-id='#{event.public_id}']", text: "Codex Browser is working"
    assert_selector "[data-agent-event-id='#{event.public_id}'] .agent-turn-spinner", visible: :all

    approval = event.agent_approvals.create!(
      request_id: { "wire" => [ "todo", event.public_id ] },
      details: { "title" => "Run todo checks" },
      options: [ { "optionId" => { "decision" => "allow" }, "name" => "Allow" } ]
    )
    assert_selector "#agent_approval_#{approval.id}", text: "Run todo checks"
    assert_selector "[data-agent-event-id='#{event.public_id}']", text: "Waiting for approval"
    assert_no_selector "[data-agent-event-id='#{event.public_id}'] .agent-turn-spinner"

    approval.resolve!({ "decision" => "allow" }, resolver: @human)
    assert_selector "[data-agent-event-id='#{event.public_id}']", text: "Codex Browser is working"
    assert_selector "[data-agent-event-id='#{event.public_id}'] .agent-turn-spinner", visible: :all

    pool.finish
    worker.value
    assert_no_selector "[data-agent-event-id='#{event.public_id}']"
    assert event.reload.delivered_at?
    assert_not @agent.reload.working?
  ensure
    pool&.finish if worker&.alive?
    worker&.join
  end

  test "approval replaces the chat spinner and its exact indexed option resumes the turn" do
    message = @project.messages.create!(author: @human, body: "@codex-browser approve deployment")
    event = message.agent_events.find_by!(recipient: @agent)
    event.transition_to!("running")

    visit chat_project_path(@project)
    assert_selector "[data-agent-event-id='#{event.public_id}']", text: "Codex Browser is working"
    assert_selector "[data-agent-event-id='#{event.public_id}'] .agent-turn-spinner", visible: :all

    approval = AgentApproval.create!(
      agent_event: event,
      request_id: "browser-permission",
      details: { "title" => "Run deployment", "tool" => "shell" },
      options: [ { "optionId" => { "decision" => "allow" }, "name" => "Allow once" }, { "optionId" => nil, "name" => "Reject" } ]
    )

    assert_selector "#agent_approval_#{approval.id}", text: "Run deployment"
    assert_no_selector "[data-agent-event-id='#{event.public_id}'] .agent-turn-spinner"
    within "#agent_approval_#{approval.id}" do
      click_button "Allow once"
    end
    assert_no_selector "#agent_approval_#{approval.id}"

    assert_equal({ "decision" => "allow" }, approval.reload.selected_option_id)
    assert_equal "running", event.reload.state
    assert_selector "[data-agent-event-id='#{event.public_id}']", text: "Codex Browser is working"
    assert_selector "[data-agent-event-id='#{event.public_id}'] .agent-turn-spinner", visible: :all

    event.transition_to!("completed")
    visit chat_project_path(@project)
    assert_no_selector "[data-agent-event-id='#{event.public_id}']"
  end
end
