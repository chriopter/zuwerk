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
    assert_equal 1, event.attempts
    assert_match(/event-correlated project message/, event.last_error)
  end
end
