class ApplicationController < ActionController::Base
  include Pundit::Authorization
  allow_browser versions: :modern
  stale_when_importmap_changes
  helper_method :current_user, :workspace_projects
  before_action :set_current_user
  before_action :set_current_account
  after_action :verify_authorized, if: -> { params[:account_number].present? && current_user&.human? }

  rescue_from Pundit::NotAuthorizedError, with: :deny_access

  def default_url_options
    Current.account ? { account_number: Current.account.account_number } : {}
  end

  private
    def current_user
      Current.user
    end

    def workspace_projects
      @workspace_projects ||= Current.account ? policy_scope(Project).order(:position, :name) : Project.none
    end

    def find_project(id)
      Current.account.projects.find(id).tap { |project| authorize(project, :show?) }
    end

    def current_account_agents
      Current.account.agents
    end

    def require_human!
      redirect_to(new_session_path(account_number: nil), alert: "Please sign in.") unless current_user&.human?
    end


    def set_current_user
      Current.user = User.find_by(id: session[:user_id])
    end

    def set_current_account
      return unless params[:account_number]

      account = Account.find_by!(account_number: params[:account_number])
      Current.account = account
      raise ActiveRecord::RecordNotFound if Current.user && !Current.user.member_of?(account)
    end

    def deny_access
      head :not_found
    end
end
