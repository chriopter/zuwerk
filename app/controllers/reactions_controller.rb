class ReactionsController < ApplicationController
  before_action :require_human!
  before_action :load_reactable

  def create
    @reactable.with_lock do
      reaction = @reactable.reactions.find_by(author: current_user, emoji: params[:emoji])
      reaction ? reaction.destroy! : @reactable.reactions.create!(author: current_user, emoji: params[:emoji])
    end
    redirect_to return_path, status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to return_path, alert: error.record.errors.full_messages.to_sentence
  end

  private

  def load_reactable
    @project = Project.find(params[:project_id])
    if params[:message_id]
      @reactable = @project.messages.find(params[:message_id])
    else
      @todo = @project.todos.find(params[:todo_id])
      @reactable = @todo.comments.find(params[:comment_id])
    end
  end

  def return_path
    return chat_project_path(@project) if @reactable.is_a?(Message)

    project_todo_path(@project, @todo, anchor: ActionView::RecordIdentifier.dom_id(@reactable))
  end
end
