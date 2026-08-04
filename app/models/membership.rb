class Membership < ApplicationRecord
  belongs_to :account
  belongs_to :user

  enum :role, { owner: 0, member: 1 }

  validates :user_id, uniqueness: { scope: :account_id }
end
