require "test_helper"

class HostedAgents::TerminalPaneRuntimeTest < ActiveSupport::TestCase
  class FakeExecutor
    attr_reader :commands

    def initialize(session_exists: false, workspace_exists: false)
      @session_exists = session_exists
      @workspace_exists = workspace_exists
      @commands = []
    end

    def run(*argv)
      @commands << argv
      if argv.include?("has-session") && !@session_exists
        raise HostedAgents::CommandExecutor::CommandError, "missing"
      end
      if argv.include?("rev-parse") && !@workspace_exists
        raise HostedAgents::CommandExecutor::CommandError, "missing workspace"
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

  test "clones the configured repository before opening a terminal in an empty workspace" do
    human = User.create!(name: "Bootstrap Human", email: "bootstrap-human@example.com", password: "password1")
    agent = User.create!(name: "Bootstrap Agent", kind: :agent)
    hosted = HostedAgent.create!(user: agent, runtime: "claude", state: "running")
    pane = Project.create!(name: "Bootstrap Project").agent_terminal_panes.create!(hosted_agent: hosted, creator: human, name: "Code")
    executor = FakeExecutor.new
    repository_url = "https://github.com/example/project.git"

    HostedAgents::TerminalPaneRuntime.new(pane, executor: executor, repository_url:).create

    assert_includes executor.commands, [ "podman", "exec", hosted.container_name, "git", "-C", "/workspace", "rev-parse", "--is-inside-work-tree" ]
    assert_includes executor.commands, [ "podman", "exec", hosted.container_name, "git", "clone", repository_url, "/workspace" ]
  end
end
