class BriefingCommentsController < ApplicationController
  before_action :require_human!
  before_action :load_records
  before_action :set_comment, only: %i[edit update destroy]
  before_action :ensure_author!, only: %i[edit update destroy]

  def create
    @comment = @briefing.comments.new(comment_params.merge(author: current_user, published_at: Time.current))
    if @comment.save
      redirect_to project_briefing_path(@project, @briefing, anchor: "briefing_comment_#{@comment.id}")
    else
      load_workspace
      render "briefings/show", status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @comment.update(comment_params)
      redirect_to project_briefing_path(@project, @briefing, anchor: "briefing_comment_#{@comment.id}")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @comment.destroy!
    redirect_to project_briefing_path(@project, @briefing)
  end

  private

  def load_records
    @project = Project.find(params[:project_id])
    @briefing = @project.briefings.find(params[:briefing_id])
  end

  def set_comment
    @comment = @briefing.comments.published.find(params[:id])
  end

  def ensure_author!
    head :forbidden unless @comment.author == current_user
  end

  def comment_params
    params.require(:briefing_comment).permit(:body)
  end

  def load_workspace
    @agents = User.agent.order(:name)
    @comments = @briefing.comments.published.chronologically.includes(:author, :rich_text_body, reactions: :author)
    @latest_run = @briefing.comments.where.not(scheduled_for: nil).includes(:agent_event).order(scheduled_for: :desc, id: :desc).first
    @latest_result = @briefing.comments.published.where.not(scheduled_for: nil).includes(:author, :rich_text_body).order(scheduled_for: :desc, id: :desc).first
  end
end
