require "test_helper"

class ChatUpgradeTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    @agent = User.create!(name: "Hermes", kind: :agent, api_token: "agent-token")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "project tree lists projects and creates a new project" do
    other = Project.create!(name: "Client launch")

    get root_path
    assert_response :success
    assert_select ".workspace-mark", count: 0
    assert_select ".workspace-sidebar .sidebar-project-tree" do
      assert_select ".sidebar-project-heading", text: /Zuwerk/
      assert_select ".sidebar-project-heading", text: /Client launch/
      assert_select "a[href='#{chat_project_path(other)}']", text: /Chat/
      assert_select ".sidebar-project-create form[action='#{projects_path}']"
    end

    assert_difference "Project.count", 1 do
      post projects_path, params: { project: { name: "Internal tools" } }
    end
    project = Project.find_by!(name: "Internal tools")
    assert_redirected_to chat_project_path(project)
    assert_equal project, project.room_setting.project
  end

  test "each project has one isolated chat and notify setting" do
    first = Project.default
    second = Project.create!(name: "Second project")
    first.messages.create!(author: @human, body: "First-only message")
    second.messages.create!(author: @human, body: "Second-only message")

    get chat_project_path(first)
    assert_response :success
    assert_select "#messages", text: /First-only message/
    assert_select "#messages", text: /Second-only message/, count: 0

    get chat_project_path(second)
    assert_response :success
    assert_select "a.sidebar-object[href='#{chat_project_path(second)}']", text: /Chat/
    assert_select "#messages", text: /Second-only message/
    assert_select "#messages", text: /First-only message/, count: 0

    post project_messages_path(second), params: { message: { body: "Created in second" } }
    assert_redirected_to chat_project_path(second)
    assert_equal second, Message.order(:id).last.project

    patch project_room_setting_path(second), params: { room_setting: { notify_agents: "1" } }
    assert_redirected_to chat_project_path(second)
    assert second.room_setting.reload.notify_agents?
    assert_not first.room_setting.reload.notify_agents?
  end

  test "renders the focused shared chat shell with the active project object" do
    get root_path

    assert_response :success
    assert_select ".workspace-sidebar"
    assert_select ".sidebar-object-active", text: /Chat/
    assert_select ".chat-header-bar h1", text: "Shared chat"
    assert_select "form.notify-control"
    assert_select "a", text: /Invite agent/
    assert_select "#message-viewport #messages"
    assert_select "textarea[placeholder='Write a message…']"
    assert_select "body", text: /Decisions|Schedule|Project overview/, count: 0
  end

  test "room settings require a signed-in human" do
    project = Project.default
    delete session_path

    patch project_room_setting_path(project), params: { room_setting: { notify_agents: "1" } }

    assert_redirected_to new_session_path
    assert_not project.room_setting.reload.notify_agents?
  end

  test "authenticated humans toggle the shared room notify agents setting" do
    assert_not RoomSetting.current.notify_agents?
    patch room_setting_path, params: { room_setting: { notify_agents: "1" } }
    assert_redirected_to chat_project_path(Project.default)
    assert RoomSetting.current.reload.notify_agents?
  end

  test "notify agents wakes every agent once for human messages and never for agent messages" do
    other = User.create!(name: "Scout", kind: :agent, api_token: "other-token")
    RoomSetting.current.update!(notify_agents: true)

    assert_difference "AgentEvent.count", 2 do
      @human.messages.create!(body: "Hello @hermes")
    end
    assert_equal [ @agent.id, other.id ].sort, AgentEvent.last(2).map(&:recipient_id).sort

    assert_no_difference "AgentEvent.count" do
      @agent.messages.create!(body: "Agent response @scout")
    end
  end

  test "when notify agents is off only explicit mentions wake agents" do
    assert_difference "AgentEvent.count", 1 do
      @human.messages.create!(body: "Please ask @hermes")
    end
    assert_equal @agent, AgentEvent.last.recipient
  end

  test "agent status heartbeat can be set and cleared" do
    headers = { "Authorization" => "Bearer agent-token" }
    post api_agent_status_path, params: { status: "working", label: "Reviewing code" }, headers: headers, as: :json
    assert_response :success
    assert @agent.reload.working?
    assert_equal "Reviewing code", @agent.working_label

    post api_agent_status_path, params: { status: "idle" }, headers: headers, as: :json
    assert_response :success
    assert_not @agent.reload.working?
  end

  test "expired heartbeat is shown as idle and labels are bounded" do
    @agent.update!(working_status: true, working_label: "Building", heartbeat_at: 2.minutes.ago)
    assert_not @agent.working?
    @agent.working_label = "x" * 81
    assert_not @agent.valid?
  end
end
