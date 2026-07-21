class MessagesController < ApplicationController
  before_action :route_first_run
  before_action :require_human!

  def index
    @messages = Message.includes(:author, reactions: :user).order(:created_at).last(200)
    @message = Message.new
  end

  def create
    @message = current_user.messages.new(message_params)
    if @message.save
      redirect_to root_path, status: :see_other
    else
      @messages = Message.includes(:author, reactions: :user).order(:created_at).last(200)
      render :index, status: :unprocessable_entity
    end
  end

  private
    def route_first_run
      redirect_to new_onboarding_path unless User.human.exists?
    end

    def message_params
      params.require(:message).permit(:body)
    end
end
