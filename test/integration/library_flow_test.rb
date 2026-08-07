require "test_helper"

class LibraryFlowTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Library Human", email: "library-human@example.com", password: "password1")
    @project = Project.create!(name: "Library project")
    post session_path, params: { email: @human.email, password: "password1" }
    @root = @project.library_pages.first
  end

  test "browses creates edits moves and deletes nested pages" do
    get project_library_pages_path(@project)
    assert_redirected_to project_library_page_path(@project, @root)

    get project_library_page_path(@project, @root)
    assert_response :success
    assert_select ".library-tree-home", text: "Home"
    assert_select "lexxy-editor, trix-editor"

    post project_library_pages_path(@project), params: { library_page: { title: "Research", parent_id: @root.id } }
    child = @project.library_pages.find_by!(title: "Research")
    assert_redirected_to project_library_page_path(@project, child)
    assert_equal @root, child.parent

    patch project_library_page_path(@project, child), params: { library_page: { title: "Product research", content: "Useful findings", parent_id: "" } }
    assert_redirected_to project_library_page_path(@project, child)
    assert_nil child.reload.parent
    assert_equal "Useful findings", child.content.to_plain_text

    delete project_library_page_path(@project, child)
    assert_redirected_to project_library_page_path(@project, @root)
    assert_not LibraryPage.exists?(child.id)
  end

  test "does not expose pages from another project or account" do
    other_project = Project.create!(name: "Other library")
    other_page = other_project.library_pages.first

    get project_library_page_path(@project, other_page)
    assert_response :not_found

    other_account = Account.create!(name: "Other account")
    foreign_project = other_account.projects.create!(name: "Foreign library")
    get project_library_page_path(foreign_project, foreign_project.library_pages.first, account_number: other_account.account_number)
    assert_response :not_found
  end

  test "protects the first project page" do
    patch project_library_page_path(@project, @root), params: { library_page: { title: "Renamed" } }
    assert_equal "Home", @root.reload.title

    delete project_library_page_path(@project, @root)
    assert_redirected_to project_library_page_path(@project, @root)
    assert LibraryPage.exists?(@root.id)
  end

  test "reorders pages and nests them through the ancestry tree" do
    first = @project.library_pages.create!(title: "First", creator: @human, position: 1)
    second = @project.library_pages.create!(title: "Second", creator: @human, position: 2)

    patch reorder_project_library_page_path(@project, second), params: { parent_id: first.id, position: 0 }, as: :json
    assert_response :no_content
    assert_equal first, second.reload.parent
    assert_equal first.id.to_s, second.ancestry

    patch reorder_project_library_page_path(@project, second), params: { parent_id: nil, position: 1 }, as: :json
    assert_response :no_content
    assert_nil second.reload.parent
    assert_equal [ @root.id, second.id, first.id ], @project.library_pages.roots.ordered.pluck(:id)

    patch reorder_project_library_page_path(@project, first), params: { parent_id: second.id, position: 0 }, as: :json
    assert_response :no_content
    patch reorder_project_library_page_path(@project, second), params: { parent_id: first.id, position: 0 }, as: :json
    assert_response :unprocessable_entity
  end
end
