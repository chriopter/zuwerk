require "test_helper"

class AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Operator", email: "operator@example.com", password: "password1")
    @agent = User.create!(name: "Builder", kind: :agent)
    @hosted_agent = HostedAgent.create!(user: @agent, runtime: "claude", state: "running")
  end

  test "requires a signed-in human to change the shared folder" do
    patch agent_path(@agent), params: { agent: { shared_folder: "1" } }

    assert_redirected_to new_session_path
    assert_not @hosted_agent.reload.shared_folder?
  end

  test "human enables the shared folder and the container is recreated" do
    sign_in

    assert_enqueued_with(job: ManageHostedAgentJob, args: [ @hosted_agent, "recreate" ]) do
      patch agent_path(@agent), params: { agent: { shared_folder: "1" } }
    end

    assert_redirected_to agent_path(@agent)
    assert @hosted_agent.reload.shared_folder?
  end

  test "an unchecked box disables the shared folder" do
    @hosted_agent.update!(shared_folder: true)
    sign_in

    patch agent_path(@agent), params: { agent: { shared_folder: "0" } }

    assert_not @hosted_agent.reload.shared_folder?
  end

  test "external agents have no shared folder to change" do
    external = User.create!(name: "Remote", kind: :agent)
    sign_in

    assert_no_enqueued_jobs(only: ManageHostedAgentJob) do
      patch agent_path(external), params: { agent: { shared_folder: "1" } }
    end

    assert_redirected_to agents_path
  end

  test "creating an agent carries the shared folder choice" do
    sign_in

    post agents_path, params: { agent: { name: "Helper", runtime: "claude", shared_folder: "1" } }

    assert HostedAgent.joins(:user).find_by(users: { name: "Helper" }).shared_folder?
  end

  test "the create form offers the shared folder" do
    sign_in

    get new_agent_path

    assert_response :success
    assert_select "input[type=checkbox][name='agent[shared_folder]']"
  end

  test "the agent page reflects the current shared folder state" do
    sign_in

    get agent_path(@agent)
    assert_select "input[type=checkbox][name='agent[shared_folder]']:not([checked])"

    @hosted_agent.update!(shared_folder: true)
    get agent_path(@agent)
    assert_select "input[type=checkbox][name='agent[shared_folder]'][checked]"
  end

  private
    def sign_in
      post session_path, params: { email: @human.email, password: "password1" }
    end
end
