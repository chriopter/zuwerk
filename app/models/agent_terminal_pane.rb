class AgentTerminalPane < ApplicationRecord
  MAX_PER_PROJECT_AGENT = 20

  belongs_to :project
  belongs_to :hosted_agent
  belongs_to :creator, class_name: "User"

  before_validation :assign_tmux_window, on: :create

  validates :name, presence: true, length: { maximum: 80 }
  validates :tmux_window, presence: true, uniqueness: true, format: { with: /\Azp-[0-9a-f]{24}\z/ }
  validate :creator_is_human
  validate :project_agent_pane_limit, on: :create

  private
    def assign_tmux_window
      self.tmux_window ||= "zp-#{SecureRandom.hex(12)}"
    end

    def creator_is_human
      errors.add(:creator, "must be human") unless creator&.human?
    end

    def project_agent_pane_limit
      return if project_id.blank? || hosted_agent_id.blank?
      if self.class.where(project_id:, hosted_agent_id:).count >= MAX_PER_PROJECT_AGENT
        errors.add(:base, "At most #{MAX_PER_PROJECT_AGENT} terminals may be open for one project agent")
      end
    end
end
