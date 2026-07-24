class ProjectsController < ApplicationController
  before_action :route_first_run
  before_action :require_human!

  def index
    load_directory
  end

  def show
    @project = Project.find(params[:id])
    @task_counts = @project.tasks.group(:status).count
    @recent_tasks = @project.tasks.where.not(status: :completed).order(updated_at: :desc, id: :desc).limit(4)
    @recent_chat_messages = @project.chat.messages.includes(:author).order(created_at: :desc, id: :desc).limit(3)
    @recent_briefings = @project.briefings.recently_active.includes(:agent, comments: :rich_text_body).limit(2)
    @recent_file_entries = @project.file_entries.includes(file_attachment: :blob).order(updated_at: :desc, id: :desc).limit(4)
    @file_entries_count = @project.file_entries.count
    @inbox_items = current_user.inbox_items.where(project: @project)
      .includes(:latest_activity, :trackable)
      .recent_first
      .limit(3)
    project_events = AgentEvent
      .where(subject_type: "ChatMessage", subject_id: @project.chat.messages.select(:id))
      .or(AgentEvent.where(subject_type: "TaskAssignment", subject_id: TaskAssignment.joins(:task).where(tasks: { project_id: @project.id }).select(:id)))
      .or(AgentEvent.where(subject_type: "BriefingComment", subject_id: BriefingComment.joins(:briefing).where(briefings: { project_id: @project.id }).select(:id)))
      .order(created_at: :desc, id: :desc).includes(:recipient, :subject).limit(60).to_a
    subscribed = User.agent.where(id: @project.chat.subscriptions.select(:agent_id))
    @project_agents = (project_events.map(&:recipient) + subscribed).uniq
    @agent_recent_events = project_events.group_by(&:recipient_id).transform_values { |events| events.first(3) }
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
    end

    def route_first_run
      redirect_to new_onboarding_path unless User.human.exists?
    end

    def project_params
      params.require(:project).permit(:name)
    end
end
