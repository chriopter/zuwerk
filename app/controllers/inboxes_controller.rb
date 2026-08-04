class InboxesController < ApplicationController
  before_action :require_human!

  def show
    authorize Current.account, :show?
    @project = workspace_projects.find(params[:project_id]) if params[:project_id].present?
    @items = current_user.inbox_items
      .then { |scope| @project ? scope.where(project: @project) : scope }
      .preload(:project, :trackable, latest_activity: :actor)
      .recent_first
      .limit(50)
    @briefings = @project&.briefings&.recently_active&.preload(:agent) || []
  end

  def mark_all_read
    authorize Current.account, :show?
    scope = current_user.inbox_items.unread
    scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?
    scope.update_all(read_at: Time.current, updated_at: Time.current)
    redirect_to inbox_path(project_id: params[:project_id].presence), notice: "Inbox marked as read."
  end
end
