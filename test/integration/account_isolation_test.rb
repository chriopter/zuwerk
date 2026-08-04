require "test_helper"

class AccountIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @first_account = Account.create!(name: "First account", account_number: "10000001")
    @second_account = Account.create!(name: "Second account", account_number: "10000002")
    @owner = create_user("owner@example.com")
    @outsider = create_user("outsider@example.com")
    @agent = create_agent("First agent", "first-agent-token")
    @other_agent = create_agent("Second agent", "second-agent-token")
    @first_account.memberships.create!(user: @owner, role: :owner)
    @first_account.memberships.create!(user: @agent, role: :member)
    @second_account.memberships.create!(user: @outsider, role: :owner)
    @second_account.memberships.create!(user: @other_agent, role: :member)
    @first_project = @first_account.projects.create!(name: "First project")
    @second_project = @second_account.projects.create!(name: "Second project")
  end

  test "account URLs and Pundit deny another account" do
    sign_in(@owner)

    get project_path(@first_project, account_number: @first_account)
    assert_response :success

    get project_path(@second_project, account_number: @second_account)
    assert_response :not_found

    get project_path(@second_project, account_number: @first_account)
    assert_response :not_found
  end

  test "members cannot manage agent invitations" do
    membership = @first_account.memberships.find_by!(user: @owner)
    membership.update!(role: :member)
    sign_in(@owner)

    get new_agent_invitation_path(account_number: @first_account)
    assert_response :not_found
  end

  test "agent API tokens only expose projects from their account" do
    get api_projects_path, headers: bearer("first-agent-token"), as: :json

    assert_response :success
    assert_equal [ @first_project.id ], response.parsed_body.pluck("id")

    get api_project_path(@second_project), headers: bearer("first-agent-token"), as: :json
    assert_response :not_found
  end

  private
    def create_user(email)
      User.new(name: email.split("@").first.titleize, email: email, password: "password1", kind: :human).tap do |user|
        user.skip_automatic_test_membership = true
        user.save!
      end
    end

    def create_agent(name, token)
      User.new(name: name, kind: :agent, api_token: token).tap do |agent|
        agent.skip_automatic_test_membership = true
        agent.save!
      end
    end

    def sign_in(user)
      post session_path, params: { email: user.email, password: "password1" }
    end

    def bearer(token)
      { "Authorization" => "Bearer #{token}" }
    end
end
