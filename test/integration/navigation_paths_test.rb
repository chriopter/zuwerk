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
    assert_select "[role='status']", text: /Email or password is incorrect/

    post session_path, params: { email: " #{@human.email.upcase} ", password: "password1" }
    assert_redirected_to root_path

    delete session_path
    assert_redirected_to new_session_path

    get project_todos_path(@first_project)
    assert_redirected_to new_session_path
  end

  test "project overview and top bar navigate to project resources" do
    sign_in
    @first_project.todos.create!(creator: @human, title: "Open task", status: :open)
    @first_project.todos.create!(creator: @human, title: "Active task", status: :in_progress)

    get root_path
    assert_response :success
    assert_select ".workspace-sidebar", count: 0
    assert_select ".workspace-topbar"
    assert_select ".topbar-mobile-menu" do
      assert_select "summary[aria-label='Open account menu']"
      assert_select "a[href='#{agents_path}']", text: "Agents"
      assert_select "form[action='#{session_path}']"
    end
    assert_select ".project-overview-card", count: 2
    assert_select ".project-overview-card[data-project-id='#{@first_project.id}']" do
      assert_select "h2", text: "Alpha"
      assert_select "[data-project-fact='open']", text: /1 open/
      assert_select "[data-project-fact='in-progress']", text: /1 in progress/
      assert_select "a[href='#{project_todos_path(@first_project)}']", text: "Board"
      assert_select "a[href='#{chat_project_path(@first_project)}']", text: "Chat"
    end

    get chat_project_path(@second_project)
    assert_response :success
    assert_select ".workspace-topbar", text: /Beta/
    assert_select ".project-context-nav a[aria-current='page'][href='#{chat_project_path(@second_project)}']", text: "Chat"
    assert_select "form[action='#{project_messages_path(@second_project)}']"

    get project_todos_path(@second_project)
    assert_response :success
    assert_select ".project-context-nav a[aria-current='page'][href='#{project_todos_path(@second_project)}']", text: "Board"
    assert_select ".project-context-nav a[href='#{chat_project_path(@second_project)}']", text: "Chat"
  end

  test "empty chat todos and agents pages provide useful next actions" do
    sign_in

    get chat_project_path(@first_project)
    assert_select ".empty-conversation", text: /Start the shared chat/
    assert_select "a[href='#{new_agent_invitation_path}']"

    get project_todos_path(@first_project)
    assert_select "h1", text: "Todos"
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
