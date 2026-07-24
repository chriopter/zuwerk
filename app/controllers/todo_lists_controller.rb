class TodoListsController < ApplicationController
  before_action :require_human!

  def create
    project = Project.find(params[:project_id])
    list = project.todo_lists.new(name: params.dig(:todo_list, :name))
    list.position = (project.todo_lists.maximum(:position) || -1) + 1
    list.save!
    redirect_to project_todos_path(project)
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_todos_path(project), alert: error.record.errors.full_messages.to_sentence
  end

  def reorder
    project = Project.find(params[:project_id])
    list = project.todo_lists.find(params[:id])
    ids = project.todo_lists.order(:position, :id).pluck(:id) - [ list.id ]
    ids.insert(params[:position].to_i.clamp(0, ids.size), list.id)
    TodoList.transaction do
      ids.each_with_index { |id, index| TodoList.where(id: id).update_all(position: index) }
    end
    head :no_content
  end
end
