require "test_helper"

class AgentInvitationTest < ActiveSupport::TestCase
  test "token is one time and expires" do
    inviter = User.create!(name: "Admin", email: "admin@example.com", password: "password1")
    invitation, token = AgentInvitation.issue!(inviter: inviter)
    assert invitation.valid_token?(token)
    assert_not invitation.valid_token?("wrong")
    invitation.update!(expires_at: 1.minute.ago)
    assert_not invitation.valid_token?(token)
  end
end
