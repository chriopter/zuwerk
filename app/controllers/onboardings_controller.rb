class OnboardingsController < ApplicationController
  before_action :redirect_if_initialized

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params.merge(kind: :human, admin: true))
    @user.skip_automatic_test_membership = true
    account = Account.new(name: "#{@user.name.presence || 'My'} workspace")
    if Account.transaction { @user.save!; account.save!; account.memberships.create!(user: @user, role: :owner); account.projects.create!(name: "Zuwerk") }
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Your workspace is ready."
    end
  rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_entity
  end

  private
    def redirect_if_initialized
      redirect_to root_path if User.human.exists?
    end

    def user_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation)
    end
end
