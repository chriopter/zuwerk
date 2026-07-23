require "test_helper"

class ProjectFilesFlowTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Files Editor", email: "files-editor@example.com", password: "password1")
    @project = Project.create!(name: "Files Workspace")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "creates folders uploads files navigates and downloads inside one project" do
    post project_file_entries_path(@project), params: { project_file_entry: { kind: "folder", name: "Reports" } }
    folder = @project.file_entries.find_by!(name: "Reports")
    assert_redirected_to project_file_entries_path(@project, folder_id: folder.id)

    upload = Rack::Test::UploadedFile.new(StringIO.new("quarterly result"), "text/plain", original_filename: "result.txt")
    post project_file_entries_path(@project), params: { folder_id: folder.id, uploads: [ upload ] }
    entry = folder.children.find_by!(name: "result.txt")

    get project_file_entries_path(@project, folder_id: folder.id)
    assert_response :success
    assert_select "h1", text: "Files"
    assert_select "a[href='#{download_project_file_entry_path(@project, entry)}']", text: /result.txt/

    get download_project_file_entry_path(@project, entry)
    assert_response :success
    assert_equal "quarterly result", response.body
    assert_match(/attachment/, response.headers["Content-Disposition"])
  end

  test "keeps folders downloads and deletion inside the selected project" do
    other = Project.create!(name: "Other Files")
    folder = other.file_entries.create!(kind: "folder", name: "Private", creator: @human)

    get project_file_entries_path(@project, folder_id: folder.id)
    assert_response :not_found

    delete project_file_entry_path(@project, folder)
    assert_response :not_found
    assert ProjectFileEntry.exists?(folder.id)
  end

  test "deleting a folder removes its file records and stored attachments" do
    folder = @project.file_entries.create!(kind: "folder", name: "Temporary", creator: @human)
    entry = @project.file_entries.new(kind: "file", name: "temporary.txt", parent: folder, creator: @human)
    entry.file.attach(io: StringIO.new("temporary"), filename: "temporary.txt", content_type: "text/plain")
    entry.save!
    blob = entry.file.blob

    delete project_file_entry_path(@project, folder)

    assert_redirected_to project_file_entries_path(@project)
    assert_not ProjectFileEntry.exists?(folder.id)
    assert_not ProjectFileEntry.exists?(entry.id)
    perform_enqueued_jobs
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end
end
