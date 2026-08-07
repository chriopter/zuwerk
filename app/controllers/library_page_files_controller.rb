class LibraryPageFilesController < ApplicationController
  before_action :require_human!

  def show
    project = find_project(params[:project_id])
    page = project.library_pages.find(params[:library_page_id])
    page_file = page.files.find(params[:id])
    return head :not_found unless page_file.file.attached?

    send_data page_file.file.download,
      filename: page_file.name,
      type: page_file.file.content_type,
      disposition: "attachment"
  end
end
