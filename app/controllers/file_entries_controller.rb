class FileEntriesController < ApplicationController
  MAX_UPLOADS = 5

  before_action :require_human!
  before_action :load_project
  before_action :load_folder, only: %i[index create]
  before_action :load_entry, only: %i[download destroy]

  def index
    load_entries
  end

  def create
    if params.dig(:project_file_entry, :kind) == "folder"
      create_folder
    else
      create_uploads
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    @errors = error.respond_to?(:record) ? error.record.errors.full_messages : [ "An item with that name already exists here." ]
    load_entries
    render :index, status: :unprocessable_entity
  end

  def download
    return head :not_found unless @entry.file? && @entry.file.attached?

    send_data @entry.file.download,
      filename: @entry.name,
      type: @entry.file.content_type,
      disposition: "attachment"
  end

  def destroy
    parent = @entry.parent
    @entry.destroy!
    redirect_to project_file_entries_path(@project, folder_id: parent&.id), notice: "Item deleted."
  end

  private
    def load_project
      @project = workspace_projects.find(params[:project_id])
    end

    def load_folder
      @folder = params[:folder_id].present? ? @project.file_entries.folder.find(params[:folder_id]) : nil
    end

    def load_entry
      @entry = @project.file_entries.find(params[:id])
    end

    def load_entries
      scope = @project.file_entries.where(parent: @folder).with_attached_file
      @folders = scope.folder.order(:name_key)
      @files = scope.file.order(:name_key)
    end

    def create_folder
      folder = @project.file_entries.create!(kind: "folder", name: params.require(:project_file_entry).require(:name), parent: @folder, creator: current_user)
      redirect_to project_file_entries_path(@project, folder_id: folder.id), notice: "Folder created."
    end

    def create_uploads
      uploads = Array(params[:uploads]).compact
      raise upload_error("must be selected") if uploads.empty?
      raise upload_error("is limited to #{MAX_UPLOADS} uploads at once") if uploads.size > MAX_UPLOADS
      raise upload_error("cannot be empty") if uploads.any? { |upload| upload.size.zero? }
      raise upload_error("must be 10 MB or smaller") if uploads.any? { |upload| upload.size > ProjectFileEntry::MAX_FILE_SIZE }

      ProjectFileEntry.transaction do
        uploads.each do |upload|
          entry = @project.file_entries.new(kind: "file", name: upload.original_filename, parent: @folder, creator: current_user)
          entry.file.attach(upload)
          entry.save!
        end
      end
      redirect_to project_file_entries_path(@project, folder_id: @folder&.id), notice: "#{uploads.size} #{'file'.pluralize(uploads.size)} uploaded."
    end

    def upload_error(message)
      record = @project.file_entries.new
      record.errors.add(:file, message)
      ActiveRecord::RecordInvalid.new(record)
    end
end
