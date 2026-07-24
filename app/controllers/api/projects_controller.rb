module Api
  class ProjectsController < BaseController
    def index
      render json: Project.order(:name).map { |project| serialize(project) }
    end

    def show
      render json: serialize(Project.find(params[:id]))
    end

    def search
      project = Project.find(params[:id])
      query = params[:q].to_s.strip
      limit = Integer(params.fetch(:limit, 10), exception: false)
      return render json: { error: "Query must contain between 2 and 500 characters." }, status: :unprocessable_entity unless query.length.between?(2, 500)
      return render json: { error: "Limit must be between 1 and 20." }, status: :unprocessable_entity unless limit&.between?(1, 20)

      results = ProjectSearch.new(project).call(query, limit: limit)
      render json: {
        query: query,
        project_id: project.id,
        results: results.map do |result|
          {
            type: result.type,
            id: result.source_id,
            title: result.title,
            snippet: result.content.squish.first(320),
            url: result.url,
            score: result.score.round(4),
            created_at: result.created_at.iso8601
          }
        end
      }
    rescue ProjectSearch::Unavailable => error
      render json: { error: error.message }, status: :service_unavailable
    end

    private
      def serialize(project)
        {
          id: project.id,
          name: project.name,
          created_at: project.created_at.iso8601,
          updated_at: project.updated_at.iso8601
        }
      end
  end
end
