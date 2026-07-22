class HostedAgent < ApplicationRecord
  RUNTIMES = %w[claude codex].freeze
  STATES = %w[provisioning stopped starting running stopping error].freeze

  belongs_to :user

  validates :runtime, inclusion: { in: RUNTIMES }
  validates :state, inclusion: { in: STATES }
  validates :user_id, uniqueness: true
  validate :user_is_agent

  def container_name
    "zuwerk-agent-#{user_id}"
  end

  def claude? = runtime == "claude"
  def running? = state == "running"
  def stopped? = state == "stopped"

  private
    def user_is_agent
      errors.add(:user, "must be an agent") unless user&.agent?
    end
end
