require "test_helper"

class AgentTerminalsTest < ActionDispatch::IntegrationTest
  FakeTerminal = Struct.new(:output, :written) do
    def capture = output
    def write(input) = self.written = input
  end

  setup do
    @human = User.create!(name: "Ada", email: "terminal-ada@example.com", password: "password1")
    identity = User.create!(name: "Builder", kind: :agent)
    @hosted_agent = HostedAgent.create!(user: identity, runtime: "claude", state: "running")
    post session_path, params: { email: @human.email, password: "password1" }
    @original_factory = AgentTerminalsController.terminal_factory
  end

  teardown do
    AgentTerminalsController.terminal_factory = @original_factory
  end

  test "returns the captured pane for an authenticated human" do
    terminal = FakeTerminal.new("ready\n", nil)

    AgentTerminalsController.terminal_factory = ->(_hosted_agent) { terminal }
    get agent_terminal_path(@hosted_agent.user), as: :json

    assert_response :success
    assert_equal "ready\n", response.parsed_body["output"]
  end

  test "writes terminal input" do
    terminal = FakeTerminal.new("", nil)

    AgentTerminalsController.terminal_factory = ->(_hosted_agent) { terminal }
    patch agent_terminal_path(@hosted_agent.user), params: { input: "hello\n" }, as: :json

    assert_response :no_content
    assert_equal "hello\n", terminal.written
  end

  test "requires a signed-in human" do
    delete session_path
    get agent_terminal_path(@hosted_agent.user), as: :json

    assert_redirected_to new_session_path
  end
end
