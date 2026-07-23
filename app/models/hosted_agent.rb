class HostedAgent < ApplicationRecord
  WORKSPACE_PATH = "/workspace".freeze
  RUNTIMES = %w[claude codex].freeze
  SESSION_MODES = { "codex" => "agent-full-access", "claude" => "auto" }.freeze
  AUTONOMOUS_SESSION_MODE = "bypassPermissions".freeze
  STATES = %w[provisioning stopped starting running stopping error].freeze

  belongs_to :user
  has_many :sessions, class_name: "HostedAgentSession", dependent: :destroy
  has_many :terminal_panes, class_name: "AgentTerminalPane", dependent: :destroy

  validates :runtime, inclusion: { in: RUNTIMES }
  validates :state, inclusion: { in: STATES }
  validates :user_id, uniqueness: true
  validate :user_is_agent

  def container_name
    "zuwerk-agent-#{user_id}"
  end

  # Agents with the shared folder work on the mounted host checkout, everyone
  # else stays in their own workspace volume.
  def working_directory
    shared_folder? ? HostedAgents::ContainerRuntime::SHARED_MOUNT_PATH : WORKSPACE_PATH
  end

  # An autonomous agent stops asking a human before each action. The adapter
  # ignores a mode it does not advertise, so this widens nothing on a runtime
  # that has no such mode.
  def session_mode
    return AUTONOMOUS_SESSION_MODE if autonomous?

    SESSION_MODES.fetch(runtime, "auto")
  end

  def claude? = runtime == "claude"
  def running? = state == "running"
  def stopped? = state == "stopped"
  def bridge_connected? = running? && bridge_connected_at.present? && bridge_connected_at > 2.minutes.ago && bridge_last_error.blank?

  private
    def user_is_agent
      errors.add(:user, "must be an agent") unless user&.agent?
    end
end
