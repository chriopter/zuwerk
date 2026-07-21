module Api
  class BaseController < ActionController::API
    before_action :authenticate_agent!

    private
      def authenticate_agent!
        token = request.authorization.to_s.delete_prefix("Bearer ").presence
        @current_agent = User.agent.find_by(api_token_digest: User.digest(token)) if token
        render json: { error: "A valid bearer token is required." }, status: :unauthorized unless @current_agent
      end
  end
end
