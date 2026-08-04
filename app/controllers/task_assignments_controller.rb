class TaskAssignmentsController < ApplicationController
  before_action :require_human!
  before_action :load_records

  def create
    agent = current_account_agents.find(params[:agent_id])
    @task.assignments.find_or_create_by!(agent: agent) { |assignment| assignment.assigned_by = current_user }
    redirect_to project_task_path(@project, @task)
  end

  def destroy
    @task.assignments.find(params[:id]).destroy!
    redirect_to project_task_path(@project, @task)
  end

  private

  def load_records
    @project = find_project(params[:project_id])
    @task = @project.tasks.find(params[:task_id])
  end
end
