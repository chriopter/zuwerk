module Api
  class ProjectsController < BaseController
    def index
      render json: Project.order(:name).map { |project| serialize(project) }
    end

    def show
      render json: serialize(Project.find(params[:id]), include_room_setting: true)
    end

    private
      def serialize(project, include_room_setting: false)
        payload = {
          id: project.id,
          name: project.name,
          created_at: project.created_at.iso8601,
          updated_at: project.updated_at.iso8601
        }
        payload[:room_setting] = { notify_agents: project.room_setting.notify_agents? } if include_room_setting
        payload
      end
  end
end
