class AgentInvitationsController < ApplicationController
  before_action :require_human!

  def new; end

  def create
    @invitation, @token = AgentInvitation.issue!(inviter: current_user)
    redirect_to agent_invitation_path(@invitation, token: @token)
  end

  def show
    @invitation = current_user.agent_invitations.find(params[:id])
    @token = params[:token]
    redirect_to new_agent_invitation_path, alert: "Invitation secret is no longer available." if @token.blank? || !@invitation.valid_token?(@token)
  end
end
