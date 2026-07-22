require "test_helper"

class ReactionTest < ActiveSupport::TestCase
  test "a user can react only once with each supported emoji" do
    user = User.create!(name: "Human", email: "human@example.com", password: "password1")
    message = Message.create!(author: user, body: "Hi")
    Reaction.create!(author: user, reactable: message, emoji: "👍")
    duplicate = Reaction.new(author: user, reactable: message, emoji: "👍")
    assert_not duplicate.valid?
    assert_not Reaction.new(author: user, reactable: message, emoji: "x").valid?
  end

  test "the same author and emoji can react to different supported records" do
    user = User.create!(name: "Human", email: "reactor@example.com", password: "password1")
    project = Project.create!(name: "Reactions")
    message = Message.create!(project: project, author: user, body: "Hi")
    todo = Todo.create!(project: project, creator: user, title: "Discuss")
    comment = TodoComment.create!(todo: todo, author: user, body: "Update")

    assert Reaction.create!(author: user, reactable: message, emoji: "🎉")
    assert Reaction.create!(author: user, reactable: comment, emoji: "🎉")
  end
end
