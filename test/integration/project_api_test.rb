require "test_helper"

class ProjectApiTest < ActionDispatch::IntegrationTest
  setup do
    @agent = User.create!(name: "Helper", kind: :agent, api_token: "agent-token")
    @project = Project.create!(name: "Launch")
    @other_project = Project.create!(name: "Archive")
    @headers = { "Authorization" => "Bearer agent-token" }
  end

  test "agent lists projects and views room setting summary" do
    @project.room_setting.update!(notify_agents: true)

    get api_projects_path, headers: @headers, as: :json

    assert_response :success
    assert_equal [ "Archive", "Launch" ], response.parsed_body.map { |project| project.fetch("name") }

    get api_project_path(@project), headers: @headers, as: :json

    assert_response :success
    assert_equal @project.id, response.parsed_body.fetch("id")
    assert_equal "Launch", response.parsed_body.fetch("name")
    assert_equal({ "notify_agents" => true }, response.parsed_body.fetch("room_setting"))
  end

  test "project API requires bearer authentication and returns JSON for missing records" do
    get api_projects_path, as: :json
    assert_response :unauthorized
    assert_equal "A valid bearer token is required.", response.parsed_body.fetch("error")

    get api_project_path(-1), headers: @headers, as: :json
    assert_response :not_found
    assert_equal "Project not found.", response.parsed_body.fetch("error")
  end

  test "agent lists and creates messages only through a project" do
    @project.messages.create!(author: @agent, body: "Launch message")
    @other_project.messages.create!(author: @agent, body: "Archived message")

    get api_project_messages_path(@project), headers: @headers, as: :json

    assert_response :success
    assert_equal [ "Launch message" ], response.parsed_body.map { |message| message.fetch("body") }
    assert_equal({ "id" => @project.id, "name" => "Launch" }, response.parsed_body.first.fetch("project"))

    assert_difference "Message.count", 1 do
      post api_project_messages_path(@project), params: { body: "Agent update" }, headers: @headers, as: :json
    end

    assert_response :created
    assert_equal @project, Message.last.project
    refute response.parsed_body.key?("state")
  end

  test "event-correlated message creation is idempotent" do
    human = User.create!(name: "Ada", email: "ada-event@example.com", password: "password1")
    source = Message.create!(author: human, project: @project, body: "@Helper answer once")
    event = source.agent_events.find_by!(recipient: @agent)

    assert_difference "Message.count", 1 do
      post api_project_messages_path(@project), params: { body: "One answer", event_id: event.public_id }, headers: @headers, as: :json
      assert_response :created
    end
    first_id = response.parsed_body.fetch("id")

    assert_no_difference "Message.count" do
      post api_project_messages_path(@project), params: { body: "Duplicate answer", event_id: event.public_id }, headers: @headers, as: :json
      assert_response :success
    end
    assert_equal first_id, response.parsed_body.fetch("id")
    assert_equal event, Message.find(first_id).agent_event
  end

  test "an event can only be published by its recipient in its project" do
    other_agent = User.create!(name: "Other", kind: :agent, api_token: "other-token")
    human = User.create!(name: "Grace", email: "grace-event@example.com", password: "password1")
    source = Message.create!(author: human, project: @project, body: "@Helper answer")
    event = source.agent_events.find_by!(recipient: @agent)

    post api_project_messages_path(@other_project), params: { body: "Wrong project", event_id: event.public_id }, headers: @headers, as: :json
    assert_response :not_found

    post api_project_messages_path(@project), params: { body: "Wrong agent", event_id: event.public_id }, headers: { "Authorization" => "Bearer other-token" }, as: :json
    assert_response :not_found
    assert_nil event.reload.publication_message
  end

  test "unscoped message and streaming API routes do not exist" do
    get "/api/messages", headers: @headers, as: :json
    assert_response :not_found

    post "/api/messages/streams", headers: @headers, as: :json
    assert_response :not_found
  end

  test "messages have no legacy streaming state" do
    refute Message.column_names.include?("state")
    refute Message.new.respond_to?(:streaming?)
  end

  test "agent lists and creates project todos with plain text descriptions" do
    todo = @project.todos.create!(creator: @agent, title: "Prepare", description: "<strong>Ready</strong> now")
    @other_project.todos.create!(creator: @agent, title: "Ignore")

    get api_project_todos_path(@project), headers: @headers, as: :json

    assert_response :success
    assert_equal [ todo.id ], response.parsed_body.map { |item| item.fetch("id") }
    assert_equal "Ready now", response.parsed_body.first.fetch("description")

    assert_difference "Todo.count", 1 do
      post api_project_todos_path(@project), params: { title: "Ship", description: "Deploy safely", status: "open" }, headers: @headers, as: :json
    end

    assert_response :created
    payload = response.parsed_body
    assert_equal({ "id" => @project.id, "name" => "Launch" }, payload.fetch("project"))
    assert_equal({ "id" => @agent.id, "name" => "Helper", "kind" => "agent" }, payload.fetch("creator"))
    assert_equal "Deploy safely", payload.fetch("description")
    assert payload.key?("created_at")
    assert payload.key?("updated_at")
  end

  test "agent gets and updates a todo title description and status" do
    todo = @project.todos.create!(creator: @agent, title: "Prepare", description: "Draft")

    get api_project_todo_path(@project, todo), headers: @headers, as: :json
    assert_response :success
    assert_equal todo.id, response.parsed_body.fetch("id")

    patch api_project_todo_path(@project, todo), params: { title: "Ship", description: "Final notes", status: "completed" }, headers: @headers, as: :json

    assert_response :success
    assert_equal "Ship", response.parsed_body.fetch("title")
    assert_equal "Final notes", response.parsed_body.fetch("description")
    assert_equal "completed", response.parsed_body.fetch("status")
    assert todo.reload.completed?
  end

  test "todo API create and update normalize positions in both sibling lists" do
    parent = @project.todos.create!(creator: @agent, title: "Parent", position: 0)
    first = @project.todos.create!(creator: @agent, title: "First", parent: parent, position: 4)
    second = @project.todos.create!(creator: @agent, title: "Second", parent: parent, position: 4)
    foreign_root = @other_project.todos.create!(creator: @agent, title: "Foreign root", position: 7)

    post api_project_todos_path(@project), params: { title: "Inserted", parent_id: parent.id, position: 1 }, headers: @headers, as: :json
    assert_response :created
    inserted = Todo.find(response.parsed_body.fetch("id"))
    assert_equal [ [ first.id, 0 ], [ inserted.id, 1 ], [ second.id, 2 ] ], parent.children.ordered.pluck(:id, :position)

    patch api_project_todo_path(@project, inserted), params: { parent_id: "", position: 0 }, headers: @headers, as: :json
    assert_response :success
    assert_equal [ [ inserted.id, 0 ], [ parent.id, 1 ] ], @project.todos.roots.ordered.pluck(:id, :position)
    assert_equal [ [ first.id, 0 ], [ second.id, 1 ] ], parent.children.ordered.pluck(:id, :position)
    assert_equal [ [ foreign_root.id, 7 ] ], @other_project.todos.roots.ordered.pluck(:id, :position)
  end

  test "invalid todo API move rolls back accompanying updates" do
    parent = @project.todos.create!(creator: @agent, title: "Parent", position: 0)
    child = @project.todos.create!(creator: @agent, title: "Child", parent: parent, position: 0)

    patch api_project_todo_path(@project, parent), params: { title: "Changed", parent_id: child.id, position: 0 }, headers: @headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "Parent", parent.reload.title
    assert_nil parent.parent
    assert_equal [ [ child.id, 0 ] ], parent.children.ordered.pluck(:id, :position)
  end

  test "todo API rejects cross-project parents and non-integer positions" do
    foreign_parent = @other_project.todos.create!(creator: @agent, title: "Foreign", position: 8)
    todo = @project.todos.create!(creator: @agent, title: "Local", position: 3)

    patch api_project_todo_path(@project, todo), params: { parent_id: foreign_parent.id, position: 0 }, headers: @headers, as: :json
    assert_response :unprocessable_entity

    patch api_project_todo_path(@project, todo), params: { position: "middle" }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_nil todo.reload.parent
    assert_equal 3, todo.position
    assert_equal 8, foreign_parent.reload.position
  end

  test "todo validation errors are JSON and updates cannot change project or creator" do
    todo = @project.todos.create!(creator: @agent, title: "Prepare")

    post api_project_todos_path(@project), params: { title: "" }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_includes response.parsed_body.fetch("errors"), "Title can't be blank"

    patch api_project_todo_path(@project, todo), params: { title: "", project_id: @other_project.id, creator_id: -1 }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal @project, todo.reload.project
    assert_equal @agent, todo.creator
  end

  test "todo show and update have no unscoped API route" do
    get "/api/todos/1", headers: @headers, as: :json
    assert_response :not_found

    patch "/api/todos/1", params: { status: "completed" }, headers: @headers, as: :json
    assert_response :not_found
  end

  test "assigned agent reads full todo context and publishes one event-correlated comment" do
    human = User.create!(name: "Ada", email: "todo-context@example.com", password: "password1")
    parent = @project.todos.create!(creator: human, title: "Launch")
    todo = @project.todos.create!(creator: human, title: "Deploy", description: "Use the checklist", parent: parent)
    todo.comments.create!(author: human, body: "Production at <strong>14:00</strong>")
    assignment = todo.assignments.create!(agent: @agent, assigner: human)
    event = assignment.agent_events.find_by!(recipient: @agent)

    get api_project_todo_path(@project, todo), headers: @headers, as: :json
    assert_response :success
    assert_equal [ "Launch" ], response.parsed_body.fetch("ancestors").map { |item| item.fetch("title") }
    assert_equal "Production at 14:00", response.parsed_body.fetch("comments").first.fetch("body")

    assert_difference "TodoComment.count", 1 do
      post api_project_todo_comments_path(@project, todo), params: { body: "Deployment complete", event_id: event.public_id }, headers: @headers, as: :json
      assert_response :created
    end

    assert_no_difference "TodoComment.count" do
      post api_project_todo_comments_path(@project, todo), params: { body: "Duplicate", event_id: event.public_id }, headers: @headers, as: :json
      assert_response :success
    end
    assert_equal event, TodoComment.last.agent_event
  end
end
