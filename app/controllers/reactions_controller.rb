class ReactionsController < ApplicationController
  before_action :require_human!

  def create
    message = Message.find(params[:message_id])
    reaction = message.reactions.find_by(user: current_user, emoji: params[:emoji])
    reaction ? reaction.destroy! : message.reactions.create!(user: current_user, emoji: params[:emoji])
    redirect_to chat_project_path(message.project), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to chat_project_path(message.project), alert: error.record.errors.full_messages.to_sentence
  end
end
