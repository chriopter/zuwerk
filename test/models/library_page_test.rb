require "test_helper"

class LibraryPageTest < ActiveSupport::TestCase
  setup do
    @human = User.create!(name: "Page Author", email: "page-author@example.com", password: "password1")
    @project = Project.create!(name: "Page model")
    @root = @project.library_pages.first
  end

  test "supports ordered nested pages with rich content" do
    child = @project.library_pages.create!(title: " Research ", parent: @root, creator: @human, position: 0, content: "Findings")
    grandchild = @project.library_pages.create!(title: "Interviews", parent: child, creator: @human, position: 0)

    assert_equal "Research", child.title
    assert_equal [ @root, child, grandchild ], grandchild.lineage
    assert_equal "Findings", child.content.to_plain_text
    assert_equal [ child.id, grandchild.id ], child.subtree_ids
  end

  test "rejects duplicate sibling titles and cross-project parents" do
    @project.library_pages.create!(title: "Research", parent: @root, creator: @human)
    duplicate = @project.library_pages.new(title: "research", parent: @root, creator: @human)
    other_project = Project.create!(name: "Other pages")
    cross_project = other_project.library_pages.new(title: "Nested", parent: @root, creator: @human)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:title], "has already been used here"
    assert_not cross_project.valid?
    assert_includes cross_project.errors[:parent], "must belong to this project"
  end

  test "destroys descendants and imported files with a page" do
    child = @project.library_pages.create!(title: "Temporary", parent: @root, creator: @human)
    page_file = child.files.new(name: "notes.txt", creator: @human)
    page_file.file.attach(io: StringIO.new("notes"), filename: "notes.txt", content_type: "text/plain")
    page_file.save!

    assert_difference [ "LibraryPage.count", "LibraryPageFile.count" ], -1 do
      child.destroy!
    end
  end
end
