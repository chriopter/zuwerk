class AgentInvitationsController < ApplicationController
  before_action :require_human!

  def new
    @agent_profiles = AgentConnectors::Profiles.all
  end

  def create
    profile = AgentConnectors::Profiles.find(params[:profile])
    return redirect_to(new_agent_invitation_path, alert: "Choose a supported agent type.") unless profile

    @invitation, @token = AgentInvitation.issue!(inviter: current_user)
    redirect_to agent_invitation_path(@invitation, token: @token, profile: profile.id)
  end

  def show
    @invitation = current_user.agent_invitations.find(params[:id])
    @token = params[:token]
    @agent_profile = AgentConnectors::Profiles.find(params[:profile])
    if @token.blank? || !@invitation.valid_token?(@token) || !@agent_profile
      redirect_to new_agent_invitation_path, alert: "Invitation secret is no longer available."
    end
  end
end
