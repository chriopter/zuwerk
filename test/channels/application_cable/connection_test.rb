require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects an agent with a valid bearer token" do
    agent = User.create!(name: "Cable Agent", kind: :agent, api_token: "secret-token")

    connect headers: { "Authorization" => "Bearer secret-token" }

    assert_equal agent, connection.current_user
  end

  test "rejects an invalid bearer token" do
    assert_reject_connection { connect headers: { "Authorization" => "Bearer invalid" } }
  end

  test "preserves human session authentication" do
    human = User.create!(name: "Cable Human", email: "cable@example.com", password: "password1")

    connect session: { user_id: human.id }

    assert_equal human, connection.current_user
  end
end
