require "test_helper"

class ChatUpgradeTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    @agent = User.create!(name: "Hermes", kind: :agent, api_token: "agent-token")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "authenticated humans toggle the shared room notify agents setting" do
    assert_not RoomSetting.current.notify_agents?
    patch room_setting_path, params: { room_setting: { notify_agents: "1" } }
    assert_redirected_to root_path
    assert RoomSetting.current.reload.notify_agents?
  end

  test "notify agents wakes every agent once for human messages and never for agent messages" do
    other = User.create!(name: "Scout", kind: :agent, api_token: "other-token")
    RoomSetting.current.update!(notify_agents: true)

    assert_difference "AgentEvent.count", 2 do
      @human.messages.create!(body: "Hello @hermes")
    end
    assert_equal [ @agent.id, other.id ].sort, AgentEvent.last(2).map(&:recipient_id).sort

    assert_no_difference "AgentEvent.count" do
      @agent.messages.create!(body: "Agent response @scout")
    end
  end

  test "when notify agents is off only explicit mentions wake agents" do
    assert_difference "AgentEvent.count", 1 do
      @human.messages.create!(body: "Please ask @hermes")
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

  test "agent streams its own message from draft through finish" do
    headers = { "Authorization" => "Bearer agent-token" }
    post api_message_streams_path, params: {}, headers: headers, as: :json
    assert_response :created
    message = Message.last
    assert message.streaming?

    assert_equal "", message.body

    patch api_message_stream_path(message), params: { action: "append", chunk: "Hello" }, headers: headers, as: :json
    assert_response :success
    assert_equal "Hello", message.reload.body

    patch api_message_stream_path(message), params: { action: "replace", body: "Hello team" }, headers: headers, as: :json
    assert_response :success
    assert_equal "Hello team", message.reload.body

    patch api_message_stream_path(message), params: { action: "finish" }, headers: headers, as: :json
    assert_response :success
    assert message.reload.completed?

    patch api_message_stream_path(message), params: { action: "append", chunk: "!" }, headers: headers, as: :json
    assert_response :unprocessable_entity
  end

  test "agents cannot mutate another agents stream and chunk limits are enforced" do
    other = User.create!(name: "Scout", kind: :agent, api_token: "other-token")
    message = other.messages.create!(body: "Draft", state: :streaming)
    headers = { "Authorization" => "Bearer agent-token" }

    patch api_message_stream_path(message), params: { action: "append", chunk: "stolen" }, headers: headers, as: :json
    assert_response :not_found
    patch api_message_stream_path(@agent.messages.create!(body: "Draft", state: :streaming)), params: { action: "append", chunk: "x" * 1001 }, headers: headers, as: :json
    assert_response :unprocessable_entity
  end
end
