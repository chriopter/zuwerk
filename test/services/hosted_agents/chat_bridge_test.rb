require "test_helper"

class HostedAgents::ChatBridgeTest < ActiveSupport::TestCase
  class PublishingPool
    attr_reader :prompt_text

    def initialize(agent:, project:, event:)
      @agent = agent
      @project = project
      @event = event
    end

    def prompt(_hosted_agent, origin, text, **)
      @prompt_text = text
      raise "wrong origin" unless origin == @project
      @agent.messages.create!(project: @project, body: "Published through the CLI", agent_event: @event)
      yield "ACP output that must remain invisible" if block_given?
    end
  end

  class ChunkPool
    attr_reader :prompt_text

    def initialize(*chunks)
      @chunks = chunks
    end

    def prompt(*args, **)
      @prompt_text = args[2]
      @chunks.each { |chunk| yield chunk }
      { "stopReason" => "end_turn" }
    end
  end

  class SilentPool
    def prompt(*, **) = nil
  end

  class BoundaryPool
    attr_reader :active_connection

    def initialize(&during_prompt)
      @during_prompt = during_prompt
    end

    def prompt(*, **)
      @active_connection = ActiveRecord::Base.connection_pool.active_connection?
      @during_prompt&.call
      yield "stale output" if block_given?
    end
  end

  class TodoPublishingPool
    attr_reader :prompt_text

    def initialize(agent:, todo:, event:)
      @agent = agent
      @todo = todo
      @event = event
    end

    def prompt(_hosted_agent, origin, text, **)
      @prompt_text = text
      raise "wrong todo origin" unless origin == @todo
      @todo.comments.create!(author: @agent, body: "Finished in todo context", agent_event: @event)
    end
  end

  test "delivers only after the recipient publishes a message through Zuwerk" do
    human = User.create!(name: "Ada", email: "ada-bridge@example.com", password: "password1")
    klaus = User.create!(name: "Klaus", kind: :agent)
    HostedAgent.create!(user: klaus, runtime: "claude", state: "running")
    project = Project.create!(name: "Bridge Project")
    source = Message.create!(author: human, project: project, body: "@Klaus please introduce yourself")
    event = source.agent_events.find_by!(recipient: klaus)
    pool = PublishingPool.new(agent: klaus, project: project, event: event)

    assert_difference -> { klaus.messages.count }, 1 do
      HostedAgents::ChatBridge.new(event, pool: pool).deliver
    end

    assert event.reload.delivered_at?
    assert event.accepted_at?
    assert_equal [ "👍" ], source.reactions.where(author: klaus).pluck(:emoji)
    assert_equal "Published through the CLI", klaus.messages.last.body
    assert_not_includes klaus.messages.pluck(:body), "ACP output that must remain invisible"
    assert_includes pool.prompt_text, event.public_id
    assert_includes pool.prompt_text, project.id.to_s
    assert_includes pool.prompt_text, project.name
    assert_includes pool.prompt_text, source.body
    assert_includes pool.prompt_text, "zuwerk messages list --project #{project.id}"
    assert_includes pool.prompt_text, "zuwerk search --project #{project.id} --query"
    assert_includes pool.prompt_text, "ACP text output is automatically saved"
    assert_includes pool.prompt_text, "Do not publish the same final response"
  end

  test "automatically publishes one correlated ACP response in project chat" do
    human = User.create!(name: "ACP Human", email: "acp-human@example.com", password: "password1")
    agent = User.create!(name: "ACP Agent", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Automatic ACP Project")
    source = Message.create!(author: human, project: project, body: "@ACP-Agent answer")
    event = source.agent_events.find_by!(recipient: agent)

    assert_difference -> { agent.messages.count }, 1 do
      HostedAgents::ChatBridge.new(event, pool: ChunkPool.new("Automatic ", "answer")).deliver
    end

    assert_equal "Automatic answer", event.reload.publication_message.body
    assert_equal "completed", event.state
  end

  test "connector replacement during ACP IO fences stale publication and completion" do
    human = User.create!(name: "Fence Human", email: "bridge-fence-human@example.com", password: "password1")
    agent = User.create!(name: "Fence Agent", kind: :agent)
    project = Project.create!(name: "Fence Bridge Project")
    event = AgentEvent.create!(recipient: agent, subject: Message.create!(author: human, project: project, body: "Fence"), event_type: "mentioned")
    event.transition_to!("running")
    event.update_columns(connector_connection_id: "old-owner")
    pool = BoundaryPool.new { event.update_columns(connector_connection_id: "new-owner") }

    AgentConnectors::Dispatcher.new(event, connection_id: "old-owner", pool: pool).deliver

    assert_not pool.active_connection
    assert_nil event.reload.publication_message
    assert_equal "running", event.state
    assert_equal 0, event.attempts
    assert_equal "new-owner", event.connector_connection_id
  end

  test "stale connector failure cannot increment attempts or record an error" do
    human = User.create!(name: "Failure Fence Human", email: "failure-fence@example.com", password: "password1")
    agent = User.create!(name: "Failure Fence Agent", kind: :agent)
    project = Project.create!(name: "Failure Fence Project")
    event = AgentEvent.create!(recipient: agent, subject: Message.create!(author: human, project: project, body: "Fence failure"), event_type: "mentioned")
    event.transition_to!("running")
    event.update_columns(connector_connection_id: "old-owner")
    pool = Object.new
    pool.define_singleton_method(:prompt) do |*|
      event.update_columns(connector_connection_id: "new-owner")
      raise "old transport closed"
    end

    assert_raises(HostedAgents::ChatBridge::DeliveryError) do
      AgentConnectors::Dispatcher.new(event, connection_id: "old-owner", pool: pool).deliver
    end

    assert_equal 0, event.reload.attempts
    assert_nil event.last_error
    assert_equal "running", event.state
  end

  test "truncates a long multibyte ACP chat response at the message character limit" do
    human = User.create!(name: "Long ACP Human", email: "long-acp-human@example.com", password: "password1")
    agent = User.create!(name: "Long ACP Agent", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Long Automatic ACP Project")
    source = Message.create!(author: human, project: project, body: "@Long-ACP-Agent answer")
    event = source.agent_events.find_by!(recipient: agent)

    HostedAgents::ChatBridge.new(event, pool: ChunkPool.new("🙂" * 4_001)).deliver

    publication = event.reload.publication_message
    assert_equal 4_000, publication.body.length
    assert_equal "🙂" * 4_000, publication.body
    assert publication.body.valid_encoding?
    assert_equal "completed", event.state
  end

  test "automatically publishes one correlated ACP response as a todo comment" do
    human = User.create!(name: "ACP Todo Human", email: "acp-todo-human@example.com", password: "password1")
    agent = User.create!(name: "ACP Todo Agent", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "codex", state: "running")
    project = Project.create!(name: "Automatic ACP Todo Project")
    todo = project.todos.create!(creator: human, title: "Write result")
    assignment = todo.assignments.create!(agent: agent, assigner: human)
    event = assignment.agent_events.find_by!(recipient: agent)

    assert_difference -> { todo.comments.count }, 1 do
      HostedAgents::ChatBridge.new(event, pool: ChunkPool.new("Todo result")).deliver
    end

    assert_equal "Todo result", event.reload.publication_comment.body.to_plain_text
    assert_equal "completed", event.state
  end

  test "automatically publishes a scheduled board response as rich text" do
    human = User.create!(name: "Board Human", email: "board-human@example.com", password: "password1")
    agent = User.create!(name: "Board Writer", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Board Publication Project")
    automation = BoardAutomation.create!(project: project, creator: human, agent: agent, title: "Morning brief", cadence: "daily", prompt: "Summarize the project.")
    post = automation.run_now!
    event = post.agent_event
    automation.update!(prompt: "Changed after the run was queued.")
    pool = ChunkPool.new("**Strong** result")

    HostedAgents::ChatBridge.new(event, pool: pool).deliver

    assert_includes pool.prompt_text, "Summarize the project."
    assert_not_includes pool.prompt_text, "Changed after the run was queued."
    assert_equal "completed", event.reload.state
    assert event.delivered_at?
    assert post.reload.published_at?
    assert_equal "Strong result", post.body.to_plain_text.squish
    assert_includes post.body.to_s, "<strong>Strong</strong>"
  end

  test "does not overwrite an existing scheduled board publication on retry" do
    human = User.create!(name: "Board Retry Human", email: "board-retry-human@example.com", password: "password1")
    agent = User.create!(name: "Board Retry Agent", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Board Retry Project")
    automation = BoardAutomation.create!(project: project, creator: human, agent: agent, title: "Retry brief", cadence: "daily", prompt: "Summarize.")
    post = automation.run_now!
    event = post.agent_event
    post.publish!("Original result", event: event)
    original_published_at = post.published_at
    pool = ChunkPool.new("Replacement result")

    HostedAgents::ChatBridge.new(event, pool: pool).deliver

    assert_nil pool.prompt_text
    assert_equal "Original result", post.reload.body.to_plain_text
    assert_equal original_published_at, post.published_at
    assert_equal "completed", event.reload.state
  end

  test "records an error without creating a placeholder when no project message is published" do
    human = User.create!(name: "Grace", email: "grace-bridge@example.com", password: "password1")
    agent = User.create!(name: "Quiet", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Empty Bridge Project")
    source = Message.create!(author: human, project: project, body: "@Quiet answer")
    event = source.agent_events.find_by!(recipient: agent)

    assert_no_difference -> { Message.count } do
      assert_raises(HostedAgents::ChatBridge::DeliveryError) do
        HostedAgents::ChatBridge.new(event, pool: SilentPool.new).deliver
      end
    end

    assert_nil event.reload.delivered_at
    assert event.accepted_at?
    assert_equal [ "👍" ], source.reactions.where(author: agent).pluck(:emoji)
    assert_equal 1, event.attempts
    assert_match(/event-correlated project message/, event.last_error)
  end

  test "todo assignment uses a persistent todo session and requires a correlated todo comment" do
    human = User.create!(name: "Ada Todo", email: "ada-todo-bridge@example.com", password: "password1")
    klaus = User.create!(name: "Klaus Todo", kind: :agent)
    HostedAgent.create!(user: klaus, runtime: "claude", state: "running")
    project = Project.create!(name: "Todo Bridge Project")
    parent = project.todos.create!(creator: human, title: "Release")
    todo = project.todos.create!(creator: human, title: "Deploy", description: "Deploy safely", parent: parent)
    todo.comments.create!(author: human, body: "Remember the smoke test")
    assignment = todo.assignments.create!(agent: klaus, assigner: human)
    event = assignment.agent_events.find_by!(recipient: klaus)
    pool = TodoPublishingPool.new(agent: klaus, todo: todo, event: event)

    HostedAgents::ChatBridge.new(event, pool: pool).deliver

    assert event.reload.delivered_at?
    assert event.accepted_at?
    assert_equal [ "👍" ], todo.reactions.where(author: klaus).pluck(:emoji)
    assert_equal "Finished in todo context", event.publication_comment.body.to_plain_text
    assert_includes pool.prompt_text, "Todo ID: #{todo.id}"
    assert_includes pool.prompt_text, "Release"
    assert_includes pool.prompt_text, "Remember the smoke test"
    assert_includes pool.prompt_text, "zuwerk todos show #{todo.id} --project #{project.id}"
    assert_includes pool.prompt_text, "Return the final user-facing outcome through ACP"
    assert_includes pool.prompt_text, "commit the finished changes before reporting the outcome"
    assert_includes pool.prompt_text, "Include the commit hash in the final ACP response"
  end

  test "acknowledgement is idempotent when delivery is retried" do
    human = User.create!(name: "Retry Human", email: "retry-human@example.com", password: "password1")
    agent = User.create!(name: "Retry Agent", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Retry Project")
    source = Message.create!(author: human, project: project, body: "@retry-agent respond")
    event = source.agent_events.find_by!(recipient: agent)
    bridge = HostedAgents::ChatBridge.new(event, pool: SilentPool.new)

    2.times { assert_raises(HostedAgents::ChatBridge::DeliveryError) { bridge.deliver } }

    assert_equal 1, source.reactions.where(author: agent, emoji: "👍").count
    assert event.reload.failed?
    assert_not agent.reload.working?
  end

  test "long todo titles do not prevent automatic assignment delivery" do
    human = User.create!(name: "Ada Long", email: "ada-long-bridge@example.com", password: "password1")
    agent = User.create!(name: "Long-title agent", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Long Todo Project")
    todo = project.todos.create!(creator: human, title: "A" * 160)
    assignment = todo.assignments.create!(agent: agent, assigner: human)
    event = assignment.agent_events.find_by!(recipient: agent)
    bridge = HostedAgents::ChatBridge.new(event, pool: SilentPool.new)

    bridge.send(:set_working, true)

    assert_equal 80, agent.reload.working_label.length
  ensure
    bridge&.send(:set_working, false)
  end
end
