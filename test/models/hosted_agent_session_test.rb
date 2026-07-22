require "test_helper"

class HostedAgentSessionTest < ActiveSupport::TestCase
  test "belongs to a polymorphic origin and is unique per hosted agent and origin" do
    agent_user = User.create!(name: "Session agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: agent_user, runtime: "claude")
    project = Project.create!(name: "Session origin")
    session = hosted_agent.sessions.create!(origin: project, external_session_id: "cloud-1")

    assert_equal project, session.origin
    duplicate = hosted_agent.sessions.new(origin: project, external_session_id: "cloud-2")
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:origin_id, :taken)
  end

  test "describes project provenance" do
    agent_user = User.create!(name: "Provenance agent", kind: :agent)
    hosted_agent = HostedAgent.create!(user: agent_user, runtime: "codex")
    project = Project.create!(name: "Apollo")
    session = hosted_agent.sessions.create!(origin: project, external_session_id: "cloud-3")

    assert_equal "Apollo", session.origin_label
  end
end
