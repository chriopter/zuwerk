require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  test "first visit onboards administrator then supports login and chat" do
    get root_path
    assert_redirected_to new_onboarding_path

    post onboarding_path, params: { user: { name: "Ada", email: " ADA@EXAMPLE.COM ", password: "password1", password_confirmation: "password1" } }
    assert_redirected_to root_path
    assert_equal "ada@example.com", User.last.email
    assert User.last.admin?

    project = User.last.primary_account.projects.find_by!(name: "Zuwerk")
    post project_chat_messages_path(project), params: { chat_message: { body: "Hello team" } }
    assert_redirected_to project_chat_path(project)
    assert_equal "Hello team", ChatMessage.last.body

    delete session_path
    assert_redirected_to new_session_path
    post session_path, params: { email: "ada@example.com", password: "password1" }
    assert_redirected_to root_path
  end

  test "messages require login and valid bodies" do
    user = User.create!(name: "Human", email: "human@example.com", password: "password1", kind: :human)
    post project_chat_messages_path(Project.default), params: { chat_message: { body: "No" } }
    assert_redirected_to new_session_path
    post session_path, params: { email: user.email, password: "password1" }
    post project_chat_messages_path(Project.default), params: { chat_message: { body: "" } }
    assert_response :unprocessable_entity
  end

  test "human messages are created only in the selected project" do
    user = User.create!(name: "Human", email: "scoped@example.com", password: "password1", kind: :human)
    selected = Project.create!(name: "Selected")
    other = Project.create!(name: "Other")
    post session_path, params: { email: user.email, password: "password1" }

    assert_difference -> { selected.chat.messages.count }, 1 do
      assert_no_difference -> { other.chat.messages.count } do
        post project_chat_messages_path(selected), params: { chat_message: { body: "Selected only" } }
      end
    end

    assert_redirected_to project_chat_path(selected)
    assert_equal selected, ChatMessage.last.project
  end

  test "project overview composer returns to the project workspace" do
    user = User.create!(name: "Human", email: "overview@example.com", password: "password1", kind: :human)
    project = Project.create!(name: "Overview")
    post session_path, params: { email: user.email, password: "password1" }

    post project_chat_messages_path(project), params: { return_to: "project", chat_message: { body: "Sent from overview" } }

    assert_redirected_to project_path(project)
    assert_equal "Sent from overview", project.chat.messages.last.body
  end
end
