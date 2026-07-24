class ProjectsController < ApplicationController
  before_action :route_first_run
  before_action :require_human!

  def index
    load_directory
  end

  def show
    @project = Project.find(params[:id])
    @task_counts = @project.todos.group(:status).count
    @recent_todos = @project.todos.where.not(status: :completed).order(updated_at: :desc, id: :desc).limit(4)
    @recent_messages = @project.messages.includes(:author).order(created_at: :desc, id: :desc).limit(3)
    @recent_board_posts = @project.board_posts.published.includes(:author, :rich_text_body).limit(2)
    @active_board_automations_count = @project.board_automations.where(active: true).count
    @recent_file_entries = @project.file_entries.includes(file_attachment: :blob).order(updated_at: :desc, id: :desc).limit(4)
    @file_entries_count = @project.file_entries.count
  end

  def create
    project = Project.new(project_params)
    if project.save
      project.room_setting
      redirect_to projects_path
    else
      load_directory
      @create_project = project
      render :index, status: :unprocessable_entity
    end
  end

  def reorder
    project = Project.find(params[:id])
    ids = Project.order(:position, :name).pluck(:id) - [ project.id ]
    ids.insert(params[:position].to_i.clamp(0, ids.size), project.id)
    Project.transaction do
      ids.each_with_index { |id, index| Project.where(id: id).update_all(position: index) }
    end
    head :no_content
  end

  private
    def load_directory
      @projects = Project.includes(:todos).order(:position, :name)
      author_pairs = Message.distinct.pluck(:project_id, :author_id)
      assignment_pairs = TodoAssignment.joins(:todo).distinct.pluck("todos.project_id", :agent_id)
      subscription_pairs = AgentSubscription.pluck(:project_id, :agent_id)
      pairs = (author_pairs + assignment_pairs + subscription_pairs).uniq
      people = User.where(id: pairs.map(&:last)).index_by(&:id)
      @project_participants = pairs.group_by(&:first).transform_values do |entries|
        entries.filter_map { |_, user_id| people[user_id] }.uniq
      end
    end

    def route_first_run
      redirect_to new_onboarding_path unless User.human.exists?
    end

    def project_params
      params.require(:project).permit(:name)
    end
end
