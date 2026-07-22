class TodoAssignmentsController < ApplicationController
  before_action :require_human!
  before_action :load_records

  def create
    agent = User.agent.find(params[:agent_id])
    @todo.assignments.find_or_create_by!(agent: agent) { |assignment| assignment.assigner = current_user }
    redirect_to project_todo_path(@project, @todo)
  end

  def destroy
    @todo.assignments.find(params[:id]).destroy!
    redirect_to project_todo_path(@project, @todo)
  end

  private

  def load_records
    @project = Project.find(params[:project_id])
    @todo = @project.todos.find(params[:todo_id])
  end
end
