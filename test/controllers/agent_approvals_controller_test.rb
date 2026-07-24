require "test_helper"

class AgentApprovalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Resolver", email: "resolver@example.com", password: "password1")
    @agent = User.create!(name: "Approval Bot", kind: :agent)
    event = AgentEvent.create!(recipient: @agent, subject: Project.default.chat.messages.create!(author: @human, body: "Approve"), event_type: "chat_message_mentioned")
    event.transition_to!("running")
    @approval = AgentApproval.create!(agent_event: event, request_id: "request", options: [ { "optionId" => "allow" }, { "optionId" => "reject" } ], details: {})
  end

  test "requires a signed-in human" do
    patch agent_approval_path(@approval), params: { option_id: "allow" }
    assert_redirected_to new_session_path
    assert_equal "pending", @approval.reload.state
  end

  test "human can resolve and invalid or conflicting choices are rejected" do
    post session_path, params: { email: @human.email, password: "password1" }
    patch agent_approval_path(@approval), params: { option_id: "allow" }
    assert_response :no_content

    patch agent_approval_path(@approval), params: { option_id: "reject" }
    assert_response :conflict
  end

  test "HTML resolution uses a server-side option index without coercing its exact ID" do
    option_id = { "nested" => [ 1, nil, 7 ] }
    @approval.update!(options: [ { "optionId" => option_id }, { "optionId" => "0" } ])
    post session_path, params: { email: @human.email, password: "password1" }

    patch agent_approval_path(@approval), params: { option_index: "0" }

    assert_redirected_to project_chat_path(@approval.agent_event.subject.project)
    assert_equal option_id, @approval.reload.selected_option_id
  end

  test "HTML resolution returns briefing work to its briefing" do
    briefing_agent = User.create!(name: "Briefing Approval Bot", kind: :agent)
    project = Project.create!(name: "Approval Briefing")
    briefing = Briefing.create!(project: project, creator: @human, agent: briefing_agent, title: "Digest", frequency: "daily", prompt: "Publish")
    event = briefing.run_now!.agent_event
    event.transition_to!("running")
    approval = AgentApproval.create!(agent_event: event, request_id: "briefing-request", options: [ { "optionId" => "allow" } ], details: {})
    post session_path, params: { email: @human.email, password: "password1" }

    patch agent_approval_path(approval), params: { option_index: "0" }

    assert_redirected_to project_briefing_path(project, briefing)
  end

  test "rejects an invalid HTML option index" do
    post session_path, params: { email: @human.email, password: "password1" }

    patch agent_approval_path(@approval), params: { option_index: "99" }

    assert_response :unprocessable_entity
    assert_equal "pending", @approval.reload.state
  end

  test "preserves a numeric option ID from a JSON request" do
    @approval.update!(options: [ { "optionId" => 7 } ])
    post session_path, params: { email: @human.email, password: "password1" }

    patch agent_approval_path(@approval), params: { option_id: 7 }, as: :json

    assert_response :no_content
    assert_equal 7, @approval.reload.selected_option_id
  end

  test "preserves an object option ID from a JSON request" do
    option_id = { "nested" => [ 1, "x" ] }
    @approval.update!(options: [ { "optionId" => option_id } ])
    post session_path, params: { email: @human.email, password: "password1" }

    patch agent_approval_path(@approval), params: { option_id: option_id }, as: :json

    assert_response :no_content
    assert_equal option_id, @approval.reload.selected_option_id
  end

  test "accepts a null option ID when it is explicitly supplied" do
    @approval.update!(options: [ { "optionId" => nil } ])
    post session_path, params: { email: @human.email, password: "password1" }

    patch agent_approval_path(@approval), params: { option_id: nil }, as: :json

    assert_response :no_content
    assert_nil @approval.reload.selected_option_id
  end
end
