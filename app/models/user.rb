class User < ApplicationRecord
  has_secure_password validations: false
  enum :kind, { human: 0, agent: 1 }
  has_many :messages, foreign_key: :author_id, dependent: :restrict_with_error
  has_many :reactions, dependent: :destroy
  has_many :agent_invitations, foreign_key: :inviter_id, dependent: :restrict_with_error

  before_validation :normalize_email
  validates :name, presence: true, length: { maximum: 80 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }, if: :human?
  validates :password, length: { minimum: 8 }, allow_nil: true, if: :human?
  validate :human_has_password
  validates :email, absence: true, if: :agent?

  def api_token=(token)
    self.api_token_digest = self.class.digest(token)
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  private
    def normalize_email
      self.email = email.to_s.strip.downcase.presence
    end

    def human_has_password
      errors.add(:password, "must be provided") if human? && password_digest.blank?
    end
end
