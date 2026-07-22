require "test_helper"

class AgentsPageTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "ada@example.com", password: "password1", kind: :human)
    @agent = User.create!(name: "Hermes", kind: :agent, working_status: true, working_label: "Reviewing project context", heartbeat_at: Time.current)
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "lists connected CLI agents and previews server-hosted environments" do
    hosted_identity = User.create!(name: "Builder", kind: :agent)
    HostedAgent.create!(user: hosted_identity, runtime: "claude", state: "running", container_id: "container-id")

    get agents_path

    assert_response :success
    assert_select "h1", "Agents"
    assert_select ".workspace-sidebar"
    assert_select "#agents-heading[href='#{agents_path}']", text: "Agents"
    assert_select "[data-sidebar-agent-id='#{hosted_identity.id}'][data-agent-connected='false']" do
      assert_select "a[href='#{agent_path(hosted_identity)}']", text: /Builder/
      assert_select ".agent-avatar-online", count: 0
      assert_select ".agent-kind-mark", count: 1
    end
    assert_select ".sidebar-channel-active", count: 0
    assert_select "[data-agent-id='#{@agent.id}']", text: /Hermes/
    assert_select "[data-agent-origin='external']", text: /Connected via CLI/
    assert_select "[data-agent-origin='hosted']", text: /On this server/
    assert_select "a[href='#{new_agent_invitation_path}']", text: /Add agent/
  end

  test "shows resumable cloud sessions with project provenance ordered by activity" do
    hosted = HostedAgent.create!(user: @agent, runtime: "codex", state: "running")
    older_project = Project.create!(name: "Older cloud origin")
    newer_project = Project.create!(name: "Newest cloud origin")
    hosted.sessions.create!(origin: older_project, external_session_id: "session-old", last_used_at: 2.days.ago)
    hosted.sessions.create!(origin: newer_project, external_session_id: "session-new", last_used_at: 1.hour.ago)

    get agent_path(@agent)

    assert_response :success
    assert_select "[data-cloud-session]", count: 2
    assert_select "[data-cloud-session]:first-child", text: /Newest cloud origin.*Project.*Codex.*Resumable.*session-new/m
    assert_select "a[href='#{chat_project_path(newer_project)}']", text: "Newest cloud origin"
    assert_operator response.body.index("session-new"), :<, response.body.index("session-old")
    assert_select "form[action*='resume']", count: 0
  end

  test "external agents redirect back to the agents list" do
    get agent_path(@agent)

    assert_redirected_to agents_path
  end

  test "sidebar shows active work inline and hides failed work" do
    HostedAgent.create!(user: @agent, runtime: "codex", state: "running")
    project = Project.create!(name: "Sidebar work")
    todo = project.todos.create!(creator: @human, title: "A deliberately long todo title that must remain stable in the sidebar")
    event = todo.assignments.create!(agent: @agent, assigner: @human).agent_events.sole
    event.update!(accepted_at: Time.current)

    get project_todo_path(project, todo)

    assert_select "turbo-cable-stream-source[channel='Turbo::StreamsChannel']"
    assert_select ".agent-inline-work[href='#{project_todo_path(project, todo)}'][data-agent-event-id='#{event.public_id}'][aria-label='Arbeitet an #{todo.title}']" do
      assert_select ".agent-work-spinner", count: 1
    end

    event.update!(last_error: "Hosted bridge failed permanently")
    get project_todo_path(project, todo)

    assert_select ".agent-inline-work", count: 0
    assert_select ".agent-work-spinner", count: 0
  end

  test "requires a signed-in human" do
    delete session_path
    get agents_path

    assert_redirected_to new_session_path
  end
end
