require "test_helper"

class ProjectReorderTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Ada", email: "reorder@example.com", password: "password1")
    @alpha = Project.create!(name: "Alpha", position: 0)
    @beta = Project.create!(name: "Beta", position: 1)
    @gamma = Project.create!(name: "Gamma", position: 2)

    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "moves a project to the requested position and reindexes the rest" do
    patch reorder_project_path(@gamma), params: { position: 0 }, as: :json

    assert_response :no_content
    assert_equal [ "Gamma", "Alpha", "Beta" ], Project.order(:position).pluck(:name)
  end

  test "clamps out-of-range positions" do
    patch reorder_project_path(@alpha), params: { position: 99 }, as: :json

    assert_response :no_content
    assert_equal [ "Beta", "Gamma", "Alpha" ], Project.order(:position).pluck(:name)
  end

  test "directory and switcher follow the manual order" do
    patch reorder_project_path(@beta), params: { position: 0 }, as: :json
    get root_path

    assert_response :success
    names = css_select(".project-directory-card .project-directory-name").map(&:text)
    assert_equal [ "Beta", "Alpha", "Gamma" ], names
  end

  test "requires a signed-in human" do
    delete session_path
    patch reorder_project_path(@alpha), params: { position: 1 }, as: :json

    assert_response :redirect
    assert_equal [ "Alpha", "Beta", "Gamma" ], Project.order(:position).pluck(:name)
  end
end
