require "test_helper"

class ProjectAgentsFlowTest < ActionDispatch::IntegrationTest
  class FakePaneRuntime
    class << self
      attr_accessor :created, :destroyed
    end

    def initialize(pane) = @pane = pane
    def create = self.class.created = @pane
    def destroy = self.class.destroyed = @pane
  end

  setup do
    @human = User.create!(name: "Agent Operator", email: "agent-operator@example.com", password: "password1")
    identity = User.create!(name: "Project Coder", kind: :agent)
    @hosted = HostedAgent.create!(user: identity, runtime: "codex", state: "running")
    @project = Project.create!(name: "Agent Workspace")
    post session_path, params: { email: @human.email, password: "password1" }
    AgentTerminalPanesController.runtime_factory = ->(pane) { FakePaneRuntime.new(pane) }
  end

  teardown do
    AgentTerminalPanesController.runtime_factory = ->(pane) { HostedAgents::TerminalPaneRuntime.new(pane) }
    FakePaneRuntime.created = FakePaneRuntime.destroyed = nil
  end

  test "shows project agents and spawns a direct-access tmux pane" do
    get agents_project_path(@project)
    assert_response :success
    assert_select "h1", text: "Agents"
    assert_select "[data-agent-id='#{@hosted.user_id}']", text: /Project Coder/

    assert_difference -> { @project.agent_terminal_panes.count }, 1 do
      post project_agent_terminal_panes_path(@project), params: { agent_terminal_pane: { hosted_agent_id: @hosted.id, name: "Debug shell" } }
    end

    pane = @project.agent_terminal_panes.last
    assert_equal pane, FakePaneRuntime.created
    assert_redirected_to agents_project_path(@project, anchor: "pane_#{pane.id}")
  end

  test "cannot destroy another projects pane" do
    other = Project.create!(name: "Other Agent Workspace")
    pane = other.agent_terminal_panes.create!(hosted_agent: @hosted, creator: @human, name: "Private pane")

    delete project_agent_terminal_pane_path(@project, pane)

    assert_response :not_found
    assert AgentTerminalPane.exists?(pane.id)
    assert_nil FakePaneRuntime.destroyed
  end
end
