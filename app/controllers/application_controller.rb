class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  helper_method :current_user, :workspace_projects

  private
    def current_user
      @current_user ||= User.find_by(id: session[:user_id])
    end

    def workspace_projects
      @workspace_projects ||= Project.order(:name)
    end

    def require_human!
      redirect_to(new_session_path, alert: "Please sign in.") unless current_user&.human?
    end
end
