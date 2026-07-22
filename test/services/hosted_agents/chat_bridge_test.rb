require "test_helper"

class HostedAgents::ChatBridgeTest < ActiveSupport::TestCase
  class PublishingPool
    attr_reader :prompt_text

    def initialize(agent:, project:, event:)
      @agent = agent
      @project = project
      @event = event
    end

    def prompt(_hosted_agent, origin, text)
      @prompt_text = text
      raise "wrong origin" unless origin == @project
      @agent.messages.create!(project: @project, body: "Published through the CLI", agent_event: @event)
      yield "ACP output that must remain invisible" if block_given?
    end
  end

  class SilentPool
    def prompt(*) = nil
  end

  class TodoPublishingPool
    attr_reader :prompt_text

    def initialize(agent:, todo:, event:)
      @agent = agent
      @todo = todo
      @event = event
    end

    def prompt(_hosted_agent, origin, text)
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
    assert_includes pool.prompt_text, "zuwerk messages create --project #{project.id} --event #{event.public_id} --body"
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
    assert_includes pool.prompt_text, "zuwerk todos comments create --project #{project.id} --todo #{todo.id} --event #{event.public_id}"
    assert_includes pool.prompt_text, "commit the finished changes before reporting the outcome"
    assert_includes pool.prompt_text, "Include the commit hash in your todo comment"
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
