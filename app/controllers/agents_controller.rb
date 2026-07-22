class AgentsController < ApplicationController
  before_action :require_human!
  before_action :set_workspace_navigation
  before_action :set_agent, only: %i[show start stop restart]

  def index
    @hosted_agents = HostedAgent.includes(:user).order(:created_at)
    @agents = User.agent.where.missing(:hosted_agent).order(:name)
  end

  def new
  end

  def create
    unless HostedAgent::RUNTIMES.include?(agent_params[:runtime])
      @errors = [ "Runtime is not supported" ]
      return render :new, status: :unprocessable_entity
    end

    hosted_agent = nil
    HostedAgent.transaction do
      identity = User.create!(name: agent_params[:name], kind: :agent)
      hosted_agent = HostedAgent.create!(user: identity, runtime: agent_params[:runtime], state: "provisioning")
    end
    ProvisionHostedAgentJob.perform_later(hosted_agent)
    redirect_to agent_path(hosted_agent.user), notice: "Agent environment is being created."
  rescue ActiveRecord::RecordInvalid => error
    @errors = error.record.errors.full_messages
    render :new, status: :unprocessable_entity
  end

  def show
    @hosted_agent = @agent.hosted_agent
    redirect_to agents_path, alert: "This agent uses an external environment." unless @hosted_agent
  end

  %i[start stop restart].each do |action|
    define_method(action) do
      return redirect_to(agents_path, alert: "This agent uses an external environment.") unless @agent.hosted_agent

      ManageHostedAgentJob.perform_later(@agent.hosted_agent, action.to_s)
      redirect_to agent_path(@agent), notice: "Agent #{action} requested."
    end
  end

  private
    def set_workspace_navigation
      @project = Project.default
      @projects = Project.order(:name)
      @sidebar_agents = User.agent.order(:name)
    end

    def set_agent
      @agent = User.agent.find(params[:id])
    end

    def agent_params
      params.require(:agent).permit(:name, :runtime)
    end
end
