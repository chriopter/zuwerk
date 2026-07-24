class ChatsController < ApplicationController
  before_action :route_first_run
  before_action :require_human!
  before_action :load_project

  def show
    load_chat
    @message = ChatMessage.new(project: @project)
  end

  private

  def load_project
    @project = Project.find(params[:project_id])
  end

  def load_chat
    @messages = @project.chat_messages
      .includes(:author, { attachments_attachments: :blob }, reactions: :author)
      .order(:created_at).last(200)
    @agents = User.agent.order(:name)
    @humans = User.human.order(:name)
    @auto_notify_agent_ids = @project.chat_subscriptions.pluck(:agent_id)
  end

  def route_first_run
    redirect_to new_onboarding_path unless User.human.exists?
  end
end
