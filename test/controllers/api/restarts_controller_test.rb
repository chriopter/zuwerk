require "test_helper"

class Api::RestartsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "restart-token"
    @agent = User.create!(name: "Restarting Agent", kind: :agent, api_token_digest: User.digest(@token))
    @restart_file = Rails.root.join("tmp", "restart-test-#{SecureRandom.hex(4)}.txt")
    Api::RestartsController.restart_file = -> { @restart_file }
  end

  teardown do
    Api::RestartsController.restart_file = -> { Rails.root.join("tmp", "restart.txt") }
    FileUtils.rm_f(@restart_file)
  end

  test "an authenticated agent triggers a restart" do
    post api_restart_path, headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :accepted
    assert File.exist?(@restart_file), "expected the Puma restart file to be touched"
  end

  test "an unauthenticated caller cannot restart the server" do
    post api_restart_path

    assert_response :unauthorized
    assert_not File.exist?(@restart_file)
  end

  test "a wrong token cannot restart the server" do
    post api_restart_path, headers: { "Authorization" => "Bearer nonsense" }

    assert_response :unauthorized
    assert_not File.exist?(@restart_file)
  end

  test "a human session is not an agent credential" do
    human = User.create!(name: "Operator", email: "restart-operator@example.com", password: "password1")
    post session_path, params: { email: human.email, password: "password1" }

    post api_restart_path

    assert_response :unauthorized
    assert_not File.exist?(@restart_file)
  end
end
