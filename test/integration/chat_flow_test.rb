require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  test "first visit onboards administrator then supports login and chat" do
    get root_path
    assert_redirected_to new_onboarding_path

    post onboarding_path, params: { user: { name: "Ada", email: " ADA@EXAMPLE.COM ", password: "password1", password_confirmation: "password1" } }
    assert_redirected_to root_path
    assert_equal "ada@example.com", User.last.email
    assert User.last.admin?

    post messages_path, params: { message: { body: "Hello team" } }
    assert_redirected_to chat_project_path(Project.default)
    assert_equal "Hello team", Message.last.body

    delete session_path
    assert_redirected_to new_session_path
    post session_path, params: { email: "ada@example.com", password: "password1" }
    assert_redirected_to root_path
  end

  test "messages require login and valid bodies" do
    user = User.create!(name: "Human", email: "human@example.com", password: "password1", kind: :human)
    post messages_path, params: { message: { body: "No" } }
    assert_redirected_to new_session_path
    post session_path, params: { email: user.email, password: "password1" }
    post messages_path, params: { message: { body: "" } }
    assert_response :unprocessable_entity
  end

  test "human messages are created only in the selected project" do
    user = User.create!(name: "Human", email: "scoped@example.com", password: "password1", kind: :human)
    selected = Project.create!(name: "Selected")
    other = Project.create!(name: "Other")
    post session_path, params: { email: user.email, password: "password1" }

    assert_difference -> { selected.messages.count }, 1 do
      assert_no_difference -> { other.messages.count } do
        post project_messages_path(selected), params: { message: { body: "Selected only" } }
      end
    end

    assert_redirected_to chat_project_path(selected)
    assert_equal selected, Message.last.project
  end
end
