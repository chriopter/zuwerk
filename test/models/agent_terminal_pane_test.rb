require "test_helper"

class AgentTerminalPaneTest < ActiveSupport::TestCase
  test "stores a project-scoped pane with an opaque tmux target" do
    human = User.create!(name: "Pane Creator", email: "pane-creator@example.com", password: "password1")
    agent = User.create!(name: "Pane Agent", kind: :agent)
    hosted = HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    project = Project.create!(name: "Pane Project")

    pane = project.agent_terminal_panes.create!(hosted_agent: hosted, creator: human, name: "Investigation")

    assert_match(/\Azp-[0-9a-f]{24}\z/, pane.tmux_window)
    assert_equal project, pane.project
    assert_equal hosted, pane.hosted_agent
  end
end
