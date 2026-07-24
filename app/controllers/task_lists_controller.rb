class TaskListsController < ApplicationController
  before_action :require_human!

  def create
    project = Project.find(params[:project_id])
    list = project.task_lists.new(name: params.dig(:task_list, :name))
    list.position = (project.task_lists.maximum(:position) || -1) + 1
    list.save!
    redirect_to project_tasks_path(project)
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_tasks_path(project), alert: error.record.errors.full_messages.to_sentence
  end

  def reorder
    project = Project.find(params[:project_id])
    list = project.task_lists.find(params[:id])
    ids = project.task_lists.order(:position, :id).pluck(:id) - [ list.id ]
    ids.insert(params[:position].to_i.clamp(0, ids.size), list.id)
    TaskList.transaction do
      ids.each_with_index { |id, index| TaskList.where(id: id).update_all(position: index) }
    end
    head :no_content
  end
end
