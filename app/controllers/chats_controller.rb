class ChatsController < ApplicationController
  before_action :route_first_run
  before_action :require_human!
  before_action :load_project

  def show
    load_chat
    @message = @chat.messages.new
    InboxItem.find_by(user: current_user, trackable: @chat)&.mark_read!
  end

  private

  def load_project
    @project = Project.find(params[:project_id])
  end

  def load_chat
    @chat = @project.chat
    @messages = @chat.messages
      .includes(:author, { attachments_attachments: :blob }, reactions: :author)
      .order(:created_at).last(200)
    @agents = User.agent.order(:name)
    @humans = User.human.order(:name)
    @auto_notify_agent_ids = @chat.subscriptions.pluck(:agent_id)
  end

  def route_first_run
    redirect_to new_onboarding_path unless User.human.exists?
  end
end
