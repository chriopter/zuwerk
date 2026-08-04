class AccountPolicy < ApplicationPolicy
  def show? = membership.present?
  def create? = user&.human?
  def update? = membership&.owner?
  def destroy? = membership&.owner?

  private
    def membership
      @membership ||= user&.memberships&.find_by(account: record)
    end
end
