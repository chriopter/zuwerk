module Api
  class AgentInvitationsController < ActionController::API
    def create
      digest = User.digest(params[:token].to_s)
      api_token = SecureRandom.urlsafe_base64(32)
      agent = nil
      AgentInvitation.transaction do
        invitation = AgentInvitation.lock.find_by(token_digest: digest)
        unless invitation&.valid_token?(params[:token])
          render json: { error: "Invitation is expired, invalid, or already used." }, status: :gone
          raise ActiveRecord::Rollback
        end
        agent = User.create!(name: params[:name], kind: :agent, api_token_digest: User.digest(api_token))
        invitation.update!(redeemed_at: Time.current)
      end
      return unless agent

      render json: { api_token: api_token, server_url: request.base_url, user: { id: agent.id, name: agent.name, kind: agent.kind } }, status: :created
    rescue ActiveRecord::RecordInvalid => error
      render json: { errors: error.record.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
