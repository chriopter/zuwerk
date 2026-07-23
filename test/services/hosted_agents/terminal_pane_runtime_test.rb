require "test_helper"

class HostedAgents::TerminalPaneRuntimeTest < ActiveSupport::TestCase
  class FakeExecutor
    attr_reader :commands

    def initialize(session_exists: false)
      @session_exists = session_exists
      @commands = []
    end

    def run(*argv)
      @commands << argv
      if argv.include?("has-session") && !@session_exists
        raise HostedAgents::CommandExecutor::CommandError, "missing"
      end
      ""
    end
  end

  test "creates and removes an independent tmux session with argv-safe identifiers" do
    human = User.create!(name: "Runtime Human", email: "runtime-human@example.com", password: "password1")
    agent = User.create!(name: "Runtime Agent", kind: :agent)
    hosted = HostedAgent.create!(user: agent, runtime: "codex", state: "running")
    pane = Project.create!(name: "Runtime Project").agent_terminal_panes.create!(hosted_agent: hosted, creator: human, name: "Review")
    executor = FakeExecutor.new
    runtime = HostedAgents::TerminalPaneRuntime.new(pane, executor: executor)

    runtime.create
    runtime.destroy

    assert_includes executor.commands, [ "podman", "exec", hosted.container_name, "tmux", "new-session", "-d", "-s", pane.tmux_window, "-c", "/workspace", "codex" ]
    assert_includes executor.commands, [ "podman", "exec", hosted.container_name, "tmux", "kill-session", "-t", pane.tmux_window ]
  end
end
