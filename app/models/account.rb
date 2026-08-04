class Account < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :projects, dependent: :destroy
  has_many :agent_invitations, dependent: :destroy

  before_validation :assign_account_number, on: :create

  validates :name, presence: true, length: { maximum: 80 }
  validates :account_number, presence: true, uniqueness: true, format: { with: /\A\d{8}\z/ }

  def to_param = account_number

  def agents = users.agent
  def humans = users.human
  def agent_presence_stream = "account_#{id}_agent_presence"

  def self.test_default
    raise "Test-only account requested outside the test environment" unless Rails.env.test?

    find_or_create_by!(name: "Test account")
  end

  private
    def assign_account_number
      self.account_number ||= loop do
        candidate = format("%08d", SecureRandom.random_number(100_000_000))
        break candidate unless self.class.exists?(account_number: candidate)
      end
    end
end
