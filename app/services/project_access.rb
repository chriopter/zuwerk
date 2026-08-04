class ProjectAccess
  def initialize(user)
    @user = user
  end

  def projects
    @user&.human? && Current.account ? Current.account.projects : Project.none
  end
end
