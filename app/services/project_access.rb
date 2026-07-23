class ProjectAccess
  def initialize(user)
    @user = user
  end

  def projects
    @user&.human? ? Project.all : Project.none
  end
end
