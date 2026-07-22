class User < ApplicationRecord
  has_secure_password validations: false
  enum :kind, { human: 0, agent: 1 }
  has_many :messages, foreign_key: :author_id, dependent: :restrict_with_error
  has_many :reactions, dependent: :destroy
  has_many :agent_invitations, foreign_key: :inviter_id, dependent: :restrict_with_error
  has_many :agent_events, foreign_key: :recipient_id, dependent: :restrict_with_error
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

  def working?
    agent? && working_status? && heartbeat_at.present? && heartbeat_at > WORKING_TTL.ago
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
