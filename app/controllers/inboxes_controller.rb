class InboxesController < ApplicationController
  before_action :require_human!

  def show
    @project = workspace_projects.find(params[:project_id]) if params[:project_id].present?
    @items = current_user.inbox_items
      .then { |scope| @project ? scope.where(project: @project) : scope }
      .includes(:project, :trackable, latest_activity: :actor)
      .recent_first
  end

  def mark_all_read
    scope = current_user.inbox_items.unread
    scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?
    scope.update_all(read_at: Time.current, updated_at: Time.current)
    redirect_to inbox_path(project_id: params[:project_id].presence), notice: "Inbox marked as read."
  end
end
