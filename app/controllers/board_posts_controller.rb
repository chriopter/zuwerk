class BoardPostsController < ApplicationController
  before_action :require_human!
  before_action :load_project

  def index
    @posts = @project.board_posts.published.includes(:author, :rich_text_body)
    @automations = @project.board_automations.includes(:agent).order(active: :desc, next_run_at: :asc, id: :asc)
  end

  def show
    @post = @project.board_posts.published.includes(:author, :rich_text_body).find(params[:id])
  end

  private

  def load_project
    @project = Project.find(params[:project_id])
  end
end
