class AgentInvitation < ApplicationRecord
  belongs_to :inviter, class_name: "User"
  validates :token_digest, :expires_at, presence: true

  def self.issue!(inviter:)
    token = SecureRandom.urlsafe_base64(32)
    [ create!(inviter: inviter, token_digest: User.digest(token), expires_at: 15.minutes.from_now), token ]
  end

  def valid_token?(token)
    redeemed_at.nil? && expires_at.future? && ActiveSupport::SecurityUtils.secure_compare(token_digest, User.digest(token.to_s))
  end
end
