class User < ApplicationRecord
  has_secure_password validations: false
  enum :kind, { human: 0, agent: 1 }
  has_many :messages, foreign_key: :author_id, dependent: :restrict_with_error
  has_many :reactions, foreign_key: :author_id, dependent: :destroy
  has_many :agent_invitations, foreign_key: :inviter_id, dependent: :restrict_with_error
  has_many :agent_events, foreign_key: :recipient_id, dependent: :restrict_with_error
  has_many :todo_assignments, foreign_key: :agent_id, dependent: :destroy
  has_many :agent_subscriptions, foreign_key: :agent_id, dependent: :destroy
  has_many :board_automations, foreign_key: :agent_id, dependent: :restrict_with_error
  has_many :created_board_automations, class_name: "BoardAutomation", foreign_key: :creator_id, dependent: :restrict_with_error
  has_many :created_agent_terminal_panes, class_name: "AgentTerminalPane", foreign_key: :creator_id, dependent: :destroy
  has_many :created_file_entries, class_name: "ProjectFileEntry", foreign_key: :creator_id, dependent: :restrict_with_error
  has_many :authored_board_posts, class_name: "BoardPost", foreign_key: :author_id, dependent: :restrict_with_error
  has_many :assigned_todo_assignments, class_name: "TodoAssignment", foreign_key: :assigner_id, dependent: :destroy
  has_one :hosted_agent, dependent: :destroy

  before_validation :normalize_email
  validates :name, presence: true, length: { maximum: 80 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }, if: :human?
  validates :password, length: { minimum: 8 }, allow_nil: true, if: :human?
  validate :human_has_password
  validates :email, absence: true, if: :agent?
  validates :working_label, length: { maximum: 80 }, allow_nil: true
  after_update_commit :broadcast_presence, if: :saved_change_to_presence?

  WORKING_TTL = 90.seconds
  CONNECTOR_TTL = 45.seconds

  def working?
    agent? && working_status? && heartbeat_at.present? && heartbeat_at > WORKING_TTL.ago
  end

  def external_connector_present?
    connector_connection_id.present? && connector_heartbeat_at.present? && connector_heartbeat_at > CONNECTOR_TTL.ago
  end

  def register_connector!(connection_id)
    with_lock do
      update_columns(connector_connection_id: connection_id, connector_heartbeat_at: Time.current, updated_at: Time.current)
      agent_events.where(state: %w[running waiting_for_approval]).where.not(connector_connection_id: nil)
        .update_all(connector_connection_id: connection_id, updated_at: Time.current)
    end
  end

  def heartbeat_connector!(connection_id)
    self.class.where(id: id, connector_connection_id: connection_id)
      .update_all(connector_heartbeat_at: Time.current, updated_at: Time.current) == 1
  end

  def clear_connector!(connection_id)
    self.class.where(id: id, connector_connection_id: connection_id)
      .update_all(connector_connection_id: nil, connector_heartbeat_at: nil, updated_at: Time.current) == 1
  end

  def connector_owned_by?(connection_id)
    self.class.where(id: id, connector_connection_id: connection_id)
      .where(connector_heartbeat_at: CONNECTOR_TTL.ago..)
      .exists?
  end

  def api_token=(token)
    self.api_token_digest = self.class.digest(token)
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def handle
    name.to_s.parameterize
  end

  private
    def saved_change_to_presence?
      saved_change_to_working_status? || saved_change_to_working_label? || saved_change_to_heartbeat_at?
    end

    def broadcast_presence
      broadcast_replace_to "agent_presence", target: "agent_presence", partial: "messages/agent_presence", locals: { agents: User.agent.order(:name) }
    end

    def normalize_email
      self.email = email.to_s.strip.downcase.presence
    end

    def human_has_password
      errors.add(:password, "must be provided") if human? && password_digest.blank?
    end
end
