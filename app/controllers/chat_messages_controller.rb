class ChatMessagesController < ApplicationController
  before_action :route_first_run
  before_action :require_human!
  before_action :load_project

  def create
    @message = current_user.chat_messages.new(chat_message_params.merge(chat: @project.chat))
    if @message.save
      redirect_to project_chat_path(@project), status: :see_other
    else
      load_chat
      render "chats/show", status: :unprocessable_entity
    end
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
    @auto_notify_agent_ids = @project.chat.subscriptions.pluck(:agent_id)
  end

  def route_first_run
    redirect_to new_onboarding_path unless User.human.exists?
  end

  def chat_message_params
    params.require(:chat_message).permit(:body, attachments: [])
  end
end
