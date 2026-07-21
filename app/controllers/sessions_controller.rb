class SessionsController < ApplicationController
  def new
    redirect_to new_onboarding_path unless User.human.exists?
  end

  def create
    user = User.human.find_by(email: params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      redirect_to root_path
    else
      flash.now[:alert] = "Email or password is incorrect."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path
  end
end
