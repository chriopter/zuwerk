require "test_helper"

class NavigationPathsTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "ada-navigation@example.com", password: "password1")
    @first_project = Project.create!(name: "Alpha")
    @second_project = Project.create!(name: "Beta")
  end

  test "signed-out visitors are returned to login from every workspace section" do
    [
      root_path,
      project_path(@first_project),
      chat_project_path(@first_project),
      project_todos_path(@first_project),
      agents_path
    ].each do |path|
      get path
      assert_redirected_to new_session_path, "Expected #{path} to require a human session"
    end
  end

  test "login logout and invalid credentials have predictable destinations" do
    post session_path, params: { email: @human.email.upcase, password: "wrong-password" }
    assert_response :unprocessable_entity
    assert_select "h1", text: "Sign in"
    assert_select "[role='alert']", text: /Email or password is incorrect/

    post session_path, params: { email: " #{@human.email.upcase} ", password: "password1" }
    assert_redirected_to root_path

    delete session_path
    assert_redirected_to new_session_path

    get project_todos_path(@first_project)
    assert_redirected_to new_session_path
  end

  test "project directory opens a project overview and tools use breadcrumbs" do
    sign_in
    @first_project.todos.create!(creator: @human, title: "Open task", status: :open)
    @first_project.todos.create!(creator: @human, title: "Active task", status: :in_progress)
    @first_project.messages.create!(author: @human, body: "Latest project note")

    get root_path
    assert_response :success
    assert_select ".workspace-sidebar", count: 0
    assert_select ".project-directory-card", count: 2
    assert_select ".project-directory-card[data-project-id='#{@first_project.id}']" do
      assert_select "a[href='#{project_path(@first_project)}']", text: /Alpha/
      assert_select "a[href='#{project_todos_path(@first_project)}']", count: 0
      assert_select "a[href='#{chat_project_path(@first_project)}']", count: 0
    end

    get project_path(@first_project)
    assert_response :success
    assert_select ".project-switcher" do
      assert_select "summary", text: /Alpha/
      assert_select "a[href='#{project_path(@second_project)}']", text: /Beta/
      assert_select "a[href='#{root_path}']", text: /All projects/
    end
    assert_select ".topbar-global-nav, .topbar-account", count: 0
    assert_select ".project-home h1", text: "Alpha"
    assert_select ".project-tool-card", count: 2
    assert_select "a[href='#{project_todos_path(@first_project)}']", text: /Tasks/
    assert_select "a[href='#{chat_project_path(@first_project)}']", text: /Chat/
    assert_select ".project-tool-card", text: /Latest project note/

    get chat_project_path(@first_project)
    assert_response :success
    assert_select ".project-context-nav", count: 0
    assert_select ".workspace-breadcrumb" do
      assert_select "a[href='#{project_path(@first_project)}']", text: "Alpha"
      assert_select "span[aria-current='page']", text: "Chat"
    end
    assert_select "form[action='#{project_messages_path(@first_project)}']"

    get project_todos_path(@first_project)
    assert_response :success
    assert_select ".project-context-nav", count: 0
    assert_select ".workspace-breadcrumb" do
      assert_select "a[href='#{project_path(@first_project)}']", text: "Alpha"
      assert_select "span[aria-current='page']", text: "Tasks"
    end
  end

  test "empty chat todos and agents pages provide useful next actions" do
    sign_in

    get chat_project_path(@first_project)
    assert_select ".empty-conversation", text: /Start the shared chat/
    assert_select "a[href='#{new_agent_invitation_path}']"

    get project_todos_path(@first_project)
    assert_select "h1", text: "Tasks"
    assert_select ".kanban-column", count: 3
    assert_select ".kanban-empty", text: "Todos hierher ziehen", count: 3
    assert_select "a[href='#{new_project_todo_path(@first_project)}']", text: "Neues Todo"

    get agents_path
    assert_select ".agents-empty", text: /No hosted agents/
    assert_select ".agents-empty", text: /No connected agents/
  end

  test "nested records cannot be reached through another project" do
    sign_in
    todo = @first_project.todos.create!(creator: @human, title: "Private to Alpha")
    message = @first_project.messages.create!(author: @human, body: "Alpha message")

    get project_todo_path(@second_project, todo)
    assert_response :not_found

    post project_message_reactions_path(@second_project, message), params: { emoji: "👍" }
    assert_response :not_found
    assert_empty message.reactions.reload
  end

  test "missing workspace paths return not found without creating fallback records" do
    sign_in

    assert_no_difference [ "Project.count", "Todo.count" ] do
      get project_path(-1)
      assert_response :not_found

      get chat_project_path(-1)
      assert_response :not_found

      get project_todo_path(@first_project, -1)
      assert_response :not_found

      get "/this-route-does-not-exist"
      assert_response :not_found
    end
  end

  private
    def sign_in
      post session_path, params: { email: @human.email, password: "password1" }
      assert_redirected_to root_path
    end
end
