class AccountsController < ApplicationController
  before_action :route_first_run
  before_action :require_human!

  def entry
    account = current_user.primary_account
    return redirect_to(new_onboarding_path) unless account

    redirect_to projects_path(account_number: account)
  end


  private
    def route_first_run
      redirect_to new_onboarding_path unless User.human.exists?
    end
end
