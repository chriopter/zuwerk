require "test_helper"

class ChatUpgradeTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    @agent = User.create!(name: "Hermes", kind: :agent, api_token: "agent-token")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "project overview lists projects and creates a new project" do
    other = Project.create!(name: "Client launch")

    get root_path
    assert_response :success
    assert_select ".project-directory-grid" do
      assert_select ".project-directory-card", text: /Client launch/
      assert_select "a[href='#{project_path(other)}']", text: /Client launch/
    end
    assert_select ".project-create-card form[action='#{projects_path}']"

    assert_difference "Project.count", 1 do
      post projects_path, params: { project: { name: "Internal tools" } }
    end
    project = Project.find_by!(name: "Internal tools")
    assert_redirected_to projects_path
    assert_equal [ "Tasks" ], project.task_lists.pluck(:name)
  end

  test "each project has one isolated chat and bot subscriptions" do
    first = Project.default
    second = Project.create!(name: "Second project")
    first.chat.messages.create!(author: @human, body: "First-only message")
    second.chat.messages.create!(author: @human, body: "Second-only message")

    get project_chat_path(first)
    assert_response :success
    assert_select "#messages", text: /First-only message/
    assert_select "#messages", text: /Second-only message/, count: 0

    get project_chat_path(second)
    assert_response :success
    assert_select ".project-switcher summary", text: /Second project/
    assert_select ".workspace-breadcrumb a[href='#{project_path(second)}']", text: "Second project"
    assert_select ".workspace-breadcrumb span[aria-current='page']", text: "Chat"
    assert_select "#messages", text: /Second-only message/
    assert_select "#messages", text: /First-only message/, count: 0

    post project_chat_messages_path(second), params: { chat_message: { body: "Created in second" } }
    assert_redirected_to project_chat_path(second)
    assert_equal second, ChatMessage.order(:id).last.project

    patch project_chat_subscription_path(second, @agent), params: { enabled: "1" }
    assert_redirected_to project_chat_path(second)
    assert second.chat.subscriptions.exists?(agent: @agent)
    assert_not first.chat.subscriptions.exists?(agent: @agent)
  end

  test "renders the focused shared chat shell with project navigation" do
    project = Project.default
    get project_chat_path(project)

    assert_response :success
    assert_select ".workspace-sidebar", count: 0
    assert_select ".project-context-nav", count: 0
    assert_select ".project-switcher summary", text: /#{Regexp.escape(project.name)}/
    assert_select ".workspace-breadcrumb span[aria-current='page']", text: "Chat"
    assert_select ".chat-header .workspace-breadcrumb"
    assert_select ".chat-header h1.sr-only", text: "Chat", count: 1
    assert_select "h1", count: 1
    assert_select ".avatar-stack form[action='#{project_chat_subscription_path(project, @agent)}'] button[aria-pressed='false'][title*='Hermes']"
    assert_select ".avatar-stack-item[title*='Hermes']"
    assert_select "#message-viewport #messages"
    assert_select "textarea[placeholder='Write a message…']"
    assert_select "body", text: /Decisions|Schedule|Project overview/, count: 0
  end

  test "renders Markdown safely and accepts message attachments" do
    project = Project.default
    upload = Rack::Test::UploadedFile.new(StringIO.new("release notes"), "text/plain", original_filename: "notes.txt")

    post project_chat_messages_path(project), params: { chat_message: { body: "**Bold** and *italic* <script>alert(1)</script>", attachments: [ upload ] } }

    message = ChatMessage.order(:id).last
    assert_redirected_to project_chat_path(project)
    assert_equal 1, message.attachments.count

    get project_chat_path(project)
    assert_select "#chat_message_#{message.id} .message-copy strong", text: "Bold"
    assert_select "#chat_message_#{message.id} .message-copy em", text: "italic"
    assert_select "#chat_message_#{message.id} script", count: 0
    assert_select "#chat_message_#{message.id} .message-attachment", text: /notes.txt/
  end

  test "bot subscriptions require a signed-in human" do
    project = Project.default
    delete session_path

    patch project_chat_subscription_path(project, @agent), params: { enabled: "1" }

    assert_redirected_to new_session_path
    assert_not project.chat.subscriptions.exists?(agent: @agent)
  end

  test "authenticated humans toggle one bot without changing another" do
    other = User.create!(name: "Scout", kind: :agent, api_token: "other-token")
    project = Project.default

    patch project_chat_subscription_path(project, @agent), params: { enabled: "1" }
    assert_redirected_to project_chat_path(project)
    assert project.chat.subscriptions.exists?(agent: @agent)
    assert_not project.chat.subscriptions.exists?(agent: other)

    patch project_chat_subscription_path(project, @agent), params: { enabled: "0" }
    assert_not project.chat.subscriptions.exists?(agent: @agent)
  end

  test "subscriptions and explicit mentions wake each selected bot once" do
    other = User.create!(name: "Scout", kind: :agent, api_token: "other-token")
    project = Project.default
    project.chat.subscriptions.create!(agent: other)

    assert_difference "AgentEvent.count", 2 do
      project.chat.messages.create!(author: @human, body: "Hello @hermes")
    end
    assert_equal [ @agent.id, other.id ].sort, AgentEvent.last(2).map(&:recipient_id).sort

    assert_no_difference "AgentEvent.count" do
      project.chat.messages.create!(author: @agent, body: "Agent response @scout")
    end
  end

  test "without a chat subscription only explicit mentions wake agents" do
    assert_difference "AgentEvent.count", 1 do
      @human.chat_messages.create!(chat: Project.default.chat, body: "Please ask @hermes")
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
