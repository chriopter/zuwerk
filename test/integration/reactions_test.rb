require "test_helper"

class ReactionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Human", email: "human-reactions@example.com", password: "password1")
    @project = Project.create!(name: "Reaction project")
    @message = ChatMessage.create!(project: @project, author: @user, body: "Hi")
    @task = Task.create!(project: @project, creator: @user, title: "Discuss")
    @comment = TaskComment.create!(task: @task, author: @user, body: "Update")
    post session_path, params: { email: @user.email, password: "password1" }
  end

  test "authenticated human toggles a message reaction" do
    assert_difference "Reaction.count", 1 do
      post project_chat_message_reactions_path(@project, @message), params: { emoji: "❤️" }
    end
    assert_redirected_to project_chat_path(@project)

    assert_difference "Reaction.count", -1 do
      post project_chat_message_reactions_path(@project, @message), params: { emoji: "❤️" }
    end
  end

  test "authenticated human toggles a task comment reaction and sees its count" do
    assert_difference "@comment.reactions.count", 1 do
      post project_task_comment_reactions_path(@project, @task, @comment), params: { emoji: "👍" }
    end
    assert_redirected_to project_task_path(@project, @task, anchor: "task_comment_#{@comment.id}")

    follow_redirect!
    assert_select "#task_comment_#{@comment.id} .boost-chip.is-own .boost-chip-emoji", text: "👍"
  end

  test "reaction targets are scoped to their project and task" do
    other_project = Project.create!(name: "Other reaction project")
    other_task = Task.create!(project: other_project, creator: @user, title: "Other")

    assert_no_difference "Reaction.count" do
      post project_chat_message_reactions_path(other_project, @message), params: { emoji: "🎉" }
    end
    assert_response :not_found

    assert_no_difference "Reaction.count" do
      post project_task_comment_reactions_path(@project, other_task, @comment), params: { emoji: "🎉" }
    end
    assert_response :not_found
  end

  test "agents without a human session cannot react" do
    delete session_path

    assert_no_difference "Reaction.count" do
      post project_chat_message_reactions_path(@project, @message), params: { emoji: "🎉" }
    end
    assert_redirected_to new_session_path
  end
end
