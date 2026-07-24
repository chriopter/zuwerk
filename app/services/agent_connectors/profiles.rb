module AgentConnectors
  module Profiles
    Profile = Data.define(:id, :name, :description, :install_command, :connect_command)

    ALL = [
      Profile.new(
        id: "claude",
        name: "Claude",
        description: "Connect Claude through the official ACP adapter for the Claude Agent SDK.",
        install_command: "npm install -g @agentclientprotocol/claude-agent-acp",
        connect_command: "zuwerk connect claude"
      ),
      Profile.new(
        id: "codex",
        name: "Codex",
        description: "Connect Codex through its ACP adapter with ChatGPT or API key authentication.",
        install_command: "npm install -g @agentclientprotocol/codex-acp",
        connect_command: "zuwerk connect codex"
      ),
      Profile.new(
        id: "hermes",
        name: "Hermes",
        description: "Connect a configured Hermes Agent using its native ACP server.",
        install_command: "hermes acp --check",
        connect_command: "zuwerk connect hermes"
      )
    ].freeze

    module_function

    def all
      ALL
    end

    def find(id)
      ALL.find { |profile| profile.id == id.to_s }
    end
  end
end
