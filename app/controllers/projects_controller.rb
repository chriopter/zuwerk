class ProjectsController < ApplicationController
  before_action :route_first_run
  before_action :require_human!

  def index
    load_directory
  end

  def show
    @project = Project.find(params[:id])
    @message = @project.chat.messages.new
    @recent_chat_messages = @project.chat.messages.includes(:author).order(created_at: :desc, id: :desc).limit(8).reverse
    @agents = User.agent.order(:name)
  end

  def create
    project = Project.new(project_params)
    if project.save
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
      @projects = Project.includes(:tasks).order(:position, :name)
      pairs = Participation.distinct.pluck(:project_id, :user_id)
      people = User.where(id: pairs.map(&:last)).index_by(&:id)
      @project_participants = pairs.group_by(&:first).transform_values do |entries|
        entries.filter_map { |_, user_id| people[user_id] }.uniq
      end
      @projects_with_new_messages = current_user.inbox_items.unread
        .where(project: @projects, trackable_type: "Chat")
        .pluck(:project_id)
    end

    def route_first_run
      redirect_to new_onboarding_path unless User.human.exists?
    end

    def project_params
      params.require(:project).permit(:name)
    end
end
