module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private
      def find_verified_user
        human = User.find_by(id: request.session[:user_id])
        return human if human&.human?

        token = request.headers["Authorization"].to_s.match(/\ABearer (.+)\z/)&.captures&.first
        if token.present?
          digest = User.digest(token)
          agent = User.agent.find_by(api_token_digest: digest)
          return agent if agent
        end

        reject_unauthorized_connection
      end
  end
end
