require "test_helper"

class ReactionsTest < ActionDispatch::IntegrationTest
  test "authenticated human toggles reaction" do
    user = User.create!(name: "Human", email: "human@example.com", password: "password1")
    message = Message.create!(author: user, body: "Hi")
    post session_path, params: { email: user.email, password: "password1" }
    assert_difference "Reaction.count", 1 do
      post message_reactions_path(message), params: { emoji: "❤️" }
    end
    assert_difference "Reaction.count", -1 do
      post message_reactions_path(message), params: { emoji: "❤️" }
    end
  end
end
