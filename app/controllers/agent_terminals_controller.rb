class AgentTerminalsController < ApplicationController
  class_attribute :terminal_factory, default: ->(hosted_agent) { HostedAgents::TerminalSession.new(hosted_agent) }

  before_action :require_human!
  before_action :set_terminal

  def show
    render json: { output: @terminal.capture }
  rescue HostedAgents::CommandExecutor::CommandError => error
    render json: { error: error.message.to_s.first(500) }, status: :service_unavailable
  end

  def update
    @terminal.write(params[:input].to_s)
    head :no_content
  rescue ArgumentError => error
    render json: { error: error.message }, status: :unprocessable_entity
  rescue HostedAgents::CommandExecutor::CommandError => error
    render json: { error: error.message.to_s.first(500) }, status: :service_unavailable
  end

  private
    def set_terminal
      agent = User.agent.find(params[:agent_id])
      hosted_agent = HostedAgent.find_by!(user: agent)
      @terminal = terminal_factory.call(hosted_agent)
    end
end
