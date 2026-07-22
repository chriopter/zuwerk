class MessagesController < ApplicationController
  before_action :route_first_run
  before_action :require_human!
  before_action :load_project

  def index
    @messages = @project.messages.includes(:author, reactions: :user).order(:created_at).last(200)
    @message = Message.new(project: @project)
    load_room
  end

  def create
    @message = current_user.messages.new(message_params.merge(project: @project))
    if @message.save
      redirect_to chat_path, status: :see_other
    else
      @messages = @project.messages.includes(:author, reactions: :user).order(:created_at).last(200)
      load_room
      render :index, status: :unprocessable_entity
    end
  end

  private
    def load_project
      project_id = params[:project_id].presence || params[:id].presence
      @project = project_id ? Project.find(project_id) : Project.default
      @projects = Project.order(:name)
    end

    def load_room
      @room_setting = @project.room_setting
      @agents = User.agent.order(:name)
    end

    def chat_path
      chat_project_path(@project)
    end

    def route_first_run
      redirect_to new_onboarding_path unless User.human.exists?
    end

    def message_params
      params.require(:message).permit(:body)
    end
end
