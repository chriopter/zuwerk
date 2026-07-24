require "test_helper"

class AgentConnectors::ChatBridgeTest < ActiveSupport::TestCase
  class ChunkPool
    def initialize(*chunks) = (@chunks = chunks)

    def prompt(*, **)
      @chunks.each { |chunk| yield chunk }
      { "stopReason" => "end_turn" }
    end
  end

  class PublishingPool
    def initialize(agent:, project:, event:)
      @agent = agent
      @project = project
      @event = event
    end

    def prompt(_agent, origin, _text, **)
      raise "wrong origin" unless origin == @project
      @agent.messages.create!(project: @project, body: "Published through the API", agent_event: @event)
    end
  end

  class ObservingChunkPool
    attr_reader :bodies

    def initialize
      @bodies = []
    end

    def prompt(agent, *, **)
      yield "First"
      @bodies << agent.messages.sole.body
      yield " second"
      @bodies << agent.messages.sole.body
      { "stopReason" => "end_turn" }
    end
  end

  test "publishes ACP output as one correlated project response" do
    human, agent, project, event = build_event

    assert_difference -> { agent.messages.count }, 1 do
      bridge(event, pool: ChunkPool.new("Automatic ", "answer")).deliver
    end

    assert_equal "Automatic answer", event.reload.publication_message.body
    assert_equal "completed", event.state
    assert event.delivered_at?
    assert_nil event.accepted_at
    assert_empty event.subject.reactions.where(author: agent, emoji: "👍")
  end

  test "creates the project response while ACP output is streaming" do
    _human, _agent, _project, event = build_event
    pool = ObservingChunkPool.new

    bridge(event, pool:).deliver

    assert_equal "First", pool.bodies.first
    assert_equal "First second", event.reload.publication_message.body
    assert_equal "completed", event.state
  end

  test "stores the exact prompt sent to the agent" do
    _human, _agent, project, event = build_event

    bridge(event, pool: ChunkPool.new("Answer")).deliver

    assert_includes event.reload.prompt_snapshot, "Project ID: #{project.id}"
    assert_includes event.prompt_snapshot, "Triggering message: Please answer"
    assert_includes event.prompt_snapshot, "zuwerk events acknowledge #{event.public_id}"
    assert event.prompted_at?
  end

  test "accepts a correlated response published through the API" do
    _human, agent, project, event = build_event

    bridge(event, pool: PublishingPool.new(agent:, project:, event:)).deliver

    assert_equal "Published through the API", event.reload.publication_message.body
    assert_equal "completed", event.state
  end

  test "a replacement connector fences stale output" do
    _human, _agent, _project, event = build_event
    pool = Object.new
    pool.define_singleton_method(:prompt) do |*, &on_chunk|
      event.update_columns(connector_connection_id: "replacement")
      on_chunk.call("stale")
    end

    bridge(event, pool:).deliver

    assert_nil event.reload.publication_message
    assert_equal "running", event.state
    assert_equal "replacement", event.connector_connection_id
  end

  test "removes a partial streamed response when ACP delivery fails" do
    _human, _agent, _project, event = build_event
    pool = Object.new
    pool.define_singleton_method(:prompt) do |*, &on_chunk|
      on_chunk.call("Incomplete")
      raise "connection closed"
    end

    error = assert_raises(AgentConnectors::ChatBridge::DeliveryError) do
      bridge(event, pool:).deliver
    end

    assert_includes error.message, "connection closed"
    assert_nil event.reload.publication_message
    assert_equal "running", event.state
  end

  private
    def build_event
      human = User.create!(name: "ACP Human", email: "acp-#{SecureRandom.hex(4)}@example.com", password: "password1")
      agent = User.create!(name: "ACP Agent #{SecureRandom.hex(2)}", kind: :agent)
      project = Project.create!(name: "ACP Project")
      message = Message.create!(author: human, project:, body: "Please answer")
      event = AgentEvent.create!(recipient: agent, subject: message, event_type: "mentioned")
      event.transition_to!("running")
      event.update_columns(connector_connection_id: "connector")
      [ human, agent, project, event ]
    end

    def bridge(event, pool:)
      AgentConnectors::ChatBridge.new(event, connection_id: "connector", pool:)
    end
end
