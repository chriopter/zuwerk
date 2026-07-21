require "test_helper"

class ReactionTest < ActiveSupport::TestCase
  test "a user can react only once with each supported emoji" do
    user = User.create!(name: "Human", email: "human@example.com", password: "password1")
    message = Message.create!(author: user, body: "Hi")
    Reaction.create!(user: user, message: message, emoji: "👍")
    duplicate = Reaction.new(user: user, message: message, emoji: "👍")
    assert_not duplicate.valid?
    assert_not Reaction.new(user: user, message: message, emoji: "x").valid?
  end
end
