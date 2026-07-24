require "test_helper"

class AgentsPageTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "ada@example.com", password: "password1", kind: :human)
    @agent = User.create!(name: "Hermes", kind: :agent, working_status: true, working_label: "Reviewing project context", heartbeat_at: Time.current)
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "lists externally operated agents and their connector status" do
    @agent.update_columns(connector_connection_id: "connection", connector_heartbeat_at: Time.current, connector_model: "Fable")
    offline = User.create!(name: "Builder", kind: :agent)
    project = Project.create!(name: "Prompt project")
    message = project.chat_messages.create!(author: @human, body: "Research this")
    event = AgentEvent.create!(recipient: @agent, subject: message, event_type: "chat_message_mentioned")
    event.update!(prompt_snapshot: "You are Hermes.\nInvestigate the request.", prompted_at: Time.current)

    get agents_path

    assert_response :success
    assert_select "h1", "Agents"
    assert_select ".workspace-sidebar", count: 0
    assert_select ".workspace-topbar .topbar-status-menu a[aria-current='page'][href='#{agents_path}']", text: "Agents"
    assert_select "[data-agent-id='#{@agent.id}']", text: /Hermes/
    assert_select "[data-agent-origin='external']", count: 2
    assert_select "[data-agent-id='#{@agent.id}']", text: /Working/
    assert_select "[data-agent-id='#{@agent.id}'] .agents-model", text: "Model: Fable"
    assert_select "[data-agent-id='#{offline.id}']", text: /Offline/
    assert_select "[data-agent-id='#{@agent.id}'] .agents-prompt" do
      assert_select "summary", text: /View last prompt/
      assert_select "pre", text: /Investigate the request/
    end
    assert_select "[data-agent-profile]", count: 3
    assert_select "[data-agent-profile='claude']", text: /zuwerk connect claude/
    assert_select "[data-agent-profile='codex']", text: /zuwerk connect codex/
    assert_select "[data-agent-profile='hermes']", text: /zuwerk connect hermes/
  end

  test "global navigation does not present sidebar-only work indicators" do
    project = Project.create!(name: "Sidebar work")
    task = project.tasks.create!(creator: @human, title: "A deliberately long task title that must remain stable in the sidebar")
    event = task.assignments.create!(agent: @agent, assigned_by: @human).agent_events.sole
    event.update!(accepted_at: Time.current)

    get project_task_path(project, task)

    assert_select ".workspace-topbar"
    assert_select ".agent-inline-work", count: 0

    event.update!(last_error: "Connector delivery failed permanently")
    get project_task_path(project, task)

    assert_select ".agent-inline-work", count: 0
  end

  test "requires a signed-in human" do
    delete session_path
    get agents_path

    assert_redirected_to new_session_path
  end
end
