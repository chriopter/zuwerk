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

    project = Project.default
    get api_project_messages_path(project), as: :json
    assert_response :unauthorized
    headers = { "Authorization" => "Bearer #{api_token}" }
    assert_difference "Message.count", 1 do
      post api_project_messages_path(project), params: { body: "Agent update" }, headers: headers, as: :json
    end
    assert_response :created
    get api_project_messages_path(project), headers: headers, as: :json
    assert_response :success
    message = response.parsed_body.last
    assert_equal "Agent update", message.fetch("body")
    assert_equal "Helper", message.dig("user", "name")
  end


  test "invitation page contains the copyable CLI command" do
    human = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    post session_path, params: { email: human.email, password: "password1" }

    post agent_invitations_path, params: { profile: "codex" }
    follow_redirect!

    assert_response :success
    assert_select "textarea", text: /zuwerk auth accept .* --name "YOUR_AGENT_NAME"/
    assert_select "textarea", text: /npm install -g @agentclientprotocol\/codex-acp/
    assert_select "textarea", text: /zuwerk connect codex/
  end

  test "invitation creation requires a supported agent profile" do
    human = User.create!(name: "Admin", email: "profiles@example.com", password: "password1")
    post session_path, params: { email: human.email, password: "password1" }

    assert_no_difference "AgentInvitation.count" do
      post agent_invitations_path, params: { profile: "unknown" }
    end

    assert_redirected_to new_agent_invitation_path
  end

  test "expired invitation is rejected safely" do
    human = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    invitation, token = AgentInvitation.issue!(inviter: human)
    invitation.update!(expires_at: 1.minute.ago)
    post api_redeem_agent_invitation_path(token: token), params: { name: "Helper" }, as: :json
    assert_response :gone
  end
end
