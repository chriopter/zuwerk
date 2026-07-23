require "test_helper"

class ProjectFileEntryTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Files Project")
    @human = User.create!(name: "File Creator", email: "file-creator@example.com", password: "password1")
  end

  test "builds an isolated folder tree with one file per entry" do
    folder = @project.file_entries.create!(kind: "folder", name: "Reports", creator: @human)
    entry = @project.file_entries.new(kind: "file", name: "status.txt", parent: folder, creator: @human)
    entry.file.attach(io: StringIO.new("project status"), filename: "status.txt", content_type: "text/plain")
    entry.save!

    assert folder.folder?
    assert entry.file?
    assert_equal folder, entry.parent
    assert_equal "project status", entry.file.download
  end

  test "requires file content and rejects unsafe or cross-project parents" do
    folder = @project.file_entries.create!(kind: "folder", name: "Reports", creator: @human)
    other_project = Project.create!(name: "Other Files Project")

    missing = @project.file_entries.new(kind: "file", name: "empty.txt", parent: folder, creator: @human)
    unsafe = @project.file_entries.new(kind: "folder", name: "../secrets", creator: @human)
    cross_project = other_project.file_entries.new(kind: "folder", name: "Nested", parent: folder, creator: @human)

    assert_not missing.valid?
    assert_includes missing.errors[:file], "must be attached"
    assert_not unsafe.valid?
    assert_not cross_project.valid?
  end

  test "normalizes sibling names and rejects files as parents" do
    folder = @project.file_entries.create!(kind: "folder", name: " Reports ", creator: @human)
    duplicate = @project.file_entries.new(kind: "folder", name: "reports", creator: @human)
    file = @project.file_entries.new(kind: "file", name: "notes.txt", creator: @human)
    file.file.attach(io: StringIO.new("notes"), filename: "notes.txt", content_type: "text/plain")
    file.save!
    child = @project.file_entries.new(kind: "folder", name: "Invalid child", parent: file, creator: @human)

    assert_equal "Reports", folder.name
    assert_not duplicate.valid?
    assert_not child.valid?
    assert_includes child.errors[:parent], "must be a folder in this project"
  end
end
