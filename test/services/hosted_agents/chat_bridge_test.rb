require "test_helper"

class HostedAgents::ChatBridgeTest < ActiveSupport::TestCase
  class FakePool
    attr_reader :prompt_text

    def prompt(_hosted_agent, _project, text)
      @prompt_text = text
      yield "Hello "
      yield "from Klaus."
    end
  end

  class EmptyPool
    def prompt(*)
      nil
    end
  end

  test "records empty ACP responses and completes the placeholder" do
    human = User.create!(name: "Grace", email: "grace-bridge@example.com", password: "password1")
    agent = User.create!(name: "Quiet", kind: :agent)
    HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Empty Bridge Project")
    source = Message.create!(author: human, project: project, body: "@Quiet answer")
    event = source.agent_events.find_by!(recipient: agent)

    error = assert_raises(HostedAgents::ChatBridge::DeliveryError) do
      HostedAgents::ChatBridge.new(event, pool: EmptyPool.new).deliver
    end

    assert_match(/empty response/, error.message)
    assert_equal 1, event.reload.attempts
    assert_match(/empty response/, event.last_error)
    assert event.response_message.completed?
    assert_predicate event.response_message.body, :present?
    assert_not agent.reload.working?
  end

  test "delivers a mention through the existing hosted identity" do
    human = User.create!(name: "Ada", email: "ada-bridge@example.com", password: "password1")
    klaus = User.create!(name: "Klaus", kind: :agent)
    HostedAgent.create!(user: klaus, runtime: "claude", state: "running")
    project = Project.create!(name: "Bridge Project")
    source = Message.create!(author: human, project: project, body: "@Klaus please introduce yourself")
    event = source.agent_events.find_by!(recipient: klaus)
    pool = FakePool.new

    assert_difference -> { klaus.messages.count }, 1 do
      HostedAgents::ChatBridge.new(event, pool: pool).deliver
    end

    event.reload
    response = event.response_message
    assert event.delivered_at?
    assert response.completed?
    assert_equal "Hello from Klaus.", response.body
    assert_equal klaus, response.author
    assert_equal project, response.project
    assert_includes pool.prompt_text, "Ada: @Klaus please introduce yourself"
    assert_not klaus.reload.working?
  end
end
