require "test_helper"

class AgentApiTest < ActionDispatch::IntegrationTest
  test "invitation redemption is single use and bearer token lists and posts messages" do
    human = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    invitation, token = AgentInvitation.issue!(inviter: human)

    post api_redeem_agent_invitation_path(token: token), params: { name: "Helper" }, as: :json
    assert_response :created
    payload = response.parsed_body
    api_token = payload.fetch("api_token")
    agent = User.find(payload.dig("user", "id"))
    assert agent.agent?
    assert_nil agent.password_digest
    assert_not_equal api_token, agent.api_token_digest

    assert_no_difference "User.count" do
      post api_redeem_agent_invitation_path(token: token), params: { name: "Again" }, as: :json
    end
    assert_response :gone

    get api_messages_path, as: :json
    assert_response :unauthorized
    headers = { "Authorization" => "Bearer #{api_token}" }
    assert_difference "Message.count", 1 do
      post api_messages_path, params: { body: "Agent update" }, headers: headers, as: :json
    end
    assert_response :created
    get api_messages_path, headers: headers, as: :json
    assert_response :success
    message = response.parsed_body.last
    assert_equal "Agent update", message.fetch("body")
    assert_equal "Helper", message.dig("user", "name")
  end

  test "agent API lists only messages from the selected project" do
    agent = User.create!(name: "Helper", kind: :agent, api_token: "agent-token")
    first = Project.default
    second = Project.create!(name: "Second")
    first.messages.create!(author: agent, body: "First message")
    second.messages.create!(author: agent, body: "Second message")

    get api_messages_path, params: { project_id: second.id }, headers: agent_headers, as: :json

    assert_response :success
    assert_equal [ "Second message" ], response.parsed_body.map { |message| message.fetch("body") }
    assert_equal({ "id" => second.id, "name" => "Second" }, response.parsed_body.first.fetch("project"))
  end

  test "agent API posts a message to the selected project" do
    User.create!(name: "Helper", kind: :agent, api_token: "agent-token")
    project = Project.create!(name: "Second")

    assert_difference "Message.count", 1 do
      post api_messages_path, params: { project_id: project.id, body: "New second" }, headers: agent_headers, as: :json
    end

    assert_response :created
    assert_equal project, Message.last.project
  end

  test "agent API starts a stream in the selected project" do
    User.create!(name: "Helper", kind: :agent, api_token: "agent-token")
    project = Project.create!(name: "Second")

    post api_message_streams_path, params: { project_id: project.id }, headers: agent_headers, as: :json

    assert_response :created
    assert_equal project, Message.last.project
  end

  test "invitation page contains the copyable CLI command" do
    human = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    post session_path, params: { email: human.email, password: "password1" }

    post agent_invitations_path
    follow_redirect!

    assert_response :success
    assert_select "textarea", text: /zuwerk auth accept .* --name YOUR_AGENT_NAME/
  end

  test "expired invitation is rejected safely" do
    human = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    invitation, token = AgentInvitation.issue!(inviter: human)
    invitation.update!(expires_at: 1.minute.ago)
    post api_redeem_agent_invitation_path(token: token), params: { name: "Helper" }, as: :json
    assert_response :gone
  end

  private
    def agent_headers
      { "Authorization" => "Bearer agent-token" }
    end
end
