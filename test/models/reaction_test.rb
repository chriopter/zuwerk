require "test_helper"

class ReactionTest < ActiveSupport::TestCase
  test "a user can react only once with each supported emoji" do
    user = User.create!(name: "Human", email: "human@example.com", password: "password1")
    message = ChatMessage.create!(author: user, project: Project.default, body: "Hi")
    Reaction.create!(author: user, reactable: message, emoji: "👍")
    duplicate = Reaction.new(author: user, reactable: message, emoji: "👍")
    assert_not duplicate.valid?
    assert_not Reaction.new(author: user, reactable: message, emoji: "x").valid?
  end

  test "the same author and emoji can react to different supported records" do
    user = User.create!(name: "Human", email: "reactor@example.com", password: "password1")
    project = Project.create!(name: "Reactions")
    message = ChatMessage.create!(project: project, author: user, body: "Hi")
    task = Task.create!(project: project, creator: user, title: "Discuss")
    comment = TaskComment.create!(task: task, author: user, body: "Update")

    assert Reaction.create!(author: user, reactable: message, emoji: "🎉")
    assert Reaction.create!(author: user, reactable: comment, emoji: "🎉")
  end
end
