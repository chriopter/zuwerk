class ChatMessagesController < ApplicationController
  before_action :route_first_run
  before_action :require_human!
  before_action :load_project

  def create
    @message = current_user.chat_messages.new(chat_message_params.merge(chat: @project.chat))
    @agents = current_account_agents.order(:name)

    if @message.save
      # The saved message reaches every open page over its stream, so the
      # response only has to hand back an empty composer.
      @message = @project.chat.messages.new
      respond_to do |format|
        format.turbo_stream { render :create }
        format.html { redirect_to return_path, status: :see_other }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html { render_rejection }
      end
    end
  end

  private

  def load_project
    @project = find_project(params[:project_id])
  end

  def from_project_home? = params[:return_to] == "project"

  def return_path
    from_project_home? ? project_path(@project) : project_chat_path(@project)
  end

  # The project home runs under the plain page layout, so it cannot re-render
  # the chat shell for an error; without Turbo it gets a flash instead.
  def render_rejection
    if from_project_home?
      redirect_to project_path(@project), status: :see_other, alert: @message.errors.full_messages.to_sentence
    else
      load_chat
      render "chats/show", status: :unprocessable_entity
    end
  end

  def load_chat
    @chat = @project.chat
    @messages = @chat.messages
      .includes(:author, { attachments_attachments: :blob }, reactions: :author)
      .order(:created_at).last(200)
    @humans = Current.account.humans.order(:name)
    @auto_notify_agent_ids = @project.chat.subscriptions.pluck(:agent_id)
  end

  def route_first_run
    redirect_to new_onboarding_path unless User.human.exists?
  end

  def chat_message_params
    params.require(:chat_message).permit(:body, attachments: [])
  end
end
