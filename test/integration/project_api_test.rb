require "test_helper"

class ProjectApiTest < ActionDispatch::IntegrationTest
  setup do
    @agent = User.create!(name: "Helper", kind: :agent, api_token: "agent-token")
    @project = Project.create!(name: "Launch")
    @other_project = Project.create!(name: "Archive")
    @headers = { "Authorization" => "Bearer agent-token" }
  end

  test "search rejects invalid queries and limits without loading the embedding model" do
    get search_api_project_path(@project), params: { q: "x", limit: 10 }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "Query must contain between 2 and 500 characters.", response.parsed_body.fetch("error")

    get search_api_project_path(@project), params: { q: "valid query", limit: "many" }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "Limit must be between 1 and 20.", response.parsed_body.fetch("error")
  end

  test "search reports an unavailable local embedding model without leaking internals" do
    @project.messages.create!(author: @agent, body: "Searchable context")
    failing_embedder = Object.new
    failing_embedder.define_singleton_method(:call) { |_texts| raise ProjectSearch::Unavailable, "Semantic search is temporarily unavailable." }
    original_factory = ProjectSearch.embedder_factory
    ProjectSearch.embedder_factory = -> { failing_embedder }
    begin
      get search_api_project_path(@project), params: { q: "search context" }, headers: @headers, as: :json
    ensure
      ProjectSearch.embedder_factory = original_factory
    end

    assert_response :service_unavailable
    assert_equal({ "error" => "Semantic search is temporarily unavailable." }, response.parsed_body)
  end

  test "agent semantically searches chat tasks comments and text attachments within a project" do
    human = User.create!(name: "Search Author", email: "search-api@example.com", password: "password1")
    message = @project.messages.create!(author: human, body: "Die Netzwerkverbindung wurde durch einen Neustart repariert.")
    todo = @project.todos.create!(creator: human, title: "Unrelated title", description: "Connection failure dauerhaft verhindern")
    todo.comments.create!(author: human, body: "Socket heartbeat ergänzen")
    message.attachments.attach(io: StringIO.new("Proxy und Tunnel prüfen"), filename: "diagnose.txt", content_type: "text/plain")
    @other_project.messages.create!(author: human, body: "Verbindungsproblem darf nicht sichtbar sein")
    embedder = Object.new
    embedder.define_singleton_method(:call) do |texts|
      Array(texts).map { |text| text.match?(/Verbindungsproblem|Netzwerkverbindung|Connection failure/i) ? [ 1.0, 0.0 ] : [ 0.0, 1.0 ] }
    end

    original_factory = ProjectSearch.embedder_factory
    ProjectSearch.embedder_factory = -> { embedder }
    begin
      get search_api_project_path(@project), params: { q: "Verbindungsproblem", limit: 4 }, headers: @headers, as: :json
    ensure
      ProjectSearch.embedder_factory = original_factory
    end

    assert_response :success
    payload = response.parsed_body
    assert_equal "Verbindungsproblem", payload.fetch("query")
    assert_equal @project.id, payload.fetch("project_id")
    assert_equal [ "message", "todo" ], payload.fetch("results").first(2).map { |result| result.fetch("type") }.sort
    assert payload.fetch("results").all? { |result| result.fetch("url").start_with?("/projects/#{@project.id}/") }
    assert payload.fetch("results").none? { |result| result.fetch("snippet").include?("nicht sichtbar") }
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

  test "recipient explicitly acknowledges an active event" do
    human = User.create!(name: "Ack Human", email: "ack@example.com", password: "password1")
    source = @project.messages.create!(author: human, body: "@Helper please investigate")
    event = source.agent_events.find_by!(recipient: @agent)
    event.transition_to!("running")

    assert_difference -> { source.reactions.where(author: @agent, emoji: "👍").count }, 1 do
      post api_acknowledge_agent_event_path(event.public_id), headers: @headers, as: :json
    end

    assert_response :success
    assert_equal event.public_id, response.parsed_body.fetch("id")
    assert event.reload.accepted_at?

    assert_no_difference "Reaction.count" do
      post api_acknowledge_agent_event_path(event.public_id), headers: @headers, as: :json
    end
    assert_response :success
  end

  test "agent cannot acknowledge another recipient's or queued event" do
    human = User.create!(name: "Other Ack Human", email: "other-ack@example.com", password: "password1")
    other_agent = User.create!(name: "Other Ack Agent", kind: :agent, api_token: "other-ack-token")
    source = @project.messages.create!(author: human, body: "@Helper acknowledge")
    event = source.agent_events.find_by!(recipient: @agent)

    post api_acknowledge_agent_event_path(event.public_id), headers: @headers, as: :json
    assert_response :not_found
    assert_nil event.reload.accepted_at

    event.transition_to!("running")
    post api_acknowledge_agent_event_path(event.public_id),
      headers: { "Authorization" => "Bearer other-ack-token" },
      as: :json
    assert_response :not_found
    assert_nil event.reload.accepted_at
  end

  test "project API requires bearer authentication and returns JSON for missing records" do
    get api_projects_path, as: :json
    assert_response :unauthorized
    assert_equal "A valid bearer token is required.", response.parsed_body.fetch("error")

    get api_project_path(-1), headers: @headers, as: :json
    assert_response :not_found
    assert_equal "Project not found.", response.parsed_body.fetch("error")
  end

  test "agent uploads an attachment with a message" do
    upload = Rack::Test::UploadedFile.new(StringIO.new("agent artifact"), "text/plain", original_filename: "artifact.txt")

    post api_project_messages_path(@project), params: { body: "Artifact attached", attachments: [ upload ] }, headers: @headers

    assert_response :created
    message = Message.order(:id).last
    assert_equal @agent, message.author
    assert_equal [ "artifact.txt" ], message.attachments.map { |attachment| attachment.filename.to_s }
  end

  test "agent sees attachment metadata and can download message attachments" do
    message = @project.messages.create!(author: @agent, body: "Review this")
    message.attachments.attach(io: StringIO.new("attachment contents"), filename: "brief.txt", content_type: "text/plain")
    attachment = message.attachments.first

    get api_project_messages_path(@project), headers: @headers, as: :json

    metadata = response.parsed_body.sole.fetch("attachments").sole
    assert_equal "brief.txt", metadata.fetch("filename")
    assert_equal "text/plain", metadata.fetch("content_type")
    assert_equal attachment.id, metadata.fetch("id")
    assert_equal api_project_message_attachment_path(@project, message, attachment), metadata.fetch("download_path")

    get api_project_message_attachment_path(@project, message, attachment), headers: @headers
    assert_response :success
    assert_equal "attachment contents", response.body
    assert_equal "attachment; filename=\"brief.txt\"; filename*=UTF-8''brief.txt", response.headers.fetch("Content-Disposition")
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

  test "todo assignment events cannot be published as chat messages" do
    human = User.create!(name: "Lin", email: "lin-event@example.com", password: "password1")
    todo = @project.todos.create!(creator: human, title: "Stay in todo")
    assignment = todo.assignments.create!(agent: @agent, assigner: human)
    event = assignment.agent_events.find_by!(recipient: @agent)

    assert_no_difference "Message.count" do
      post api_project_messages_path(@project), params: { body: "Wrong channel", event_id: event.public_id }, headers: @headers, as: :json
    end

    assert_response :not_found
    assert_equal "AgentEvent not found.", response.parsed_body.fetch("error")
    assert_nil event.reload.publication_message
  end

  test "invalid event-correlated message can be retried and missing events return JSON" do
    human = User.create!(name: "Mina", email: "mina-event@example.com", password: "password1")
    source = Message.create!(author: human, project: @project, body: "@Helper respond")
    event = source.agent_events.find_by!(recipient: @agent)

    post api_project_messages_path(@project), params: { body: "", event_id: event.public_id }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_includes response.parsed_body.fetch("errors"), "Body can't be blank"
    assert_nil event.reload.publication_message

    assert_difference "Message.count", 1 do
      post api_project_messages_path(@project), params: { body: "Valid retry", event_id: event.public_id }, headers: @headers, as: :json
    end
    assert_response :created

    post api_project_messages_path(@project), params: { body: "Missing", event_id: SecureRandom.uuid }, headers: @headers, as: :json
    assert_response :not_found
    assert_equal "AgentEvent not found.", response.parsed_body.fetch("error")
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

  test "mention events and assignments for another todo cannot publish todo comments" do
    human = User.create!(name: "Nora", email: "nora-context@example.com", password: "password1")
    todo = @project.todos.create!(creator: human, title: "Expected todo")
    other_todo = @project.todos.create!(creator: human, title: "Other todo")
    assignment_event = other_todo.assignments.create!(agent: @agent, assigner: human).agent_events.sole
    mention_event = Message.create!(author: human, project: @project, body: "@Helper hello").agent_events.sole

    [ assignment_event, mention_event ].each do |event|
      assert_no_difference "TodoComment.count" do
        post api_project_todo_comments_path(@project, todo), params: { body: "Wrong context", event_id: event.public_id }, headers: @headers, as: :json
      end
      assert_response :not_found
      assert_equal "AgentEvent not found.", response.parsed_body.fetch("error")
    end
  end
end
