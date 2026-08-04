class ProjectPolicy < ApplicationPolicy
  def index? = Current.account.present? && user&.member_of?(Current.account)
  def show? = user&.member_of?(record.account)
  def create? = Current.account.present? && user&.member_of?(Current.account)
  def update? = show?
  def destroy? = show?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless Current.account && user&.member_of?(Current.account)

      scope.where(account: Current.account)
    end
  end
end
