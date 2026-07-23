require "fileutils"

module Api
  # Lets a hosted agent restart the server it is working on. Puma's tmp_restart
  # plugin picks the touched file up, so the running process reboots itself and
  # no shell access is needed. Only routed outside production.
  class RestartsController < BaseController
    class_attribute :restart_file, default: -> { Rails.root.join("tmp", "restart.txt") }

    def create
      return render json: { error: "Restarts are only available in development." }, status: :not_found unless Rails.env.local?

      path = restart_file.call
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.touch(path)
      render json: { restarting: true, environment: Rails.env.to_s }, status: :accepted
    end
  end
end
