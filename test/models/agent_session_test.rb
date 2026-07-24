require "test_helper"

class AgentSessionTest < ActiveSupport::TestCase
  test "tracks the current ACP session once per agent and context" do
    human = User.create!(name: "Session Human", email: "session-human@example.com", password: "password1")
    agent = User.create!(name: "Session Agent", kind: :agent)
    project = Project.create!(name: "Session Project")
    task = project.tasks.create!(creator: human, title: "Keep context")

    first = AgentSession.record_usage!(agent: agent, context: task, external_session_id: "first")
    same = AgentSession.record_usage!(agent: agent, context: task, external_session_id: "first")

    assert_equal first, same
    assert_equal 2, same.prompt_count
    assert_equal "first", same.external_session_id

    replacement = AgentSession.record_usage!(agent: agent, context: task, external_session_id: "replacement")

    assert_equal first, replacement
    assert_equal 1, replacement.prompt_count
    assert_equal "replacement", replacement.external_session_id
    assert_equal 1, AgentSession.where(agent: agent, context: task).count
  end

  test "rejects a context from another project" do
    agent = User.create!(name: "Session Agent", kind: :agent)
    first = Project.create!(name: "First")
    second = Project.create!(name: "Second")

    session = AgentSession.new(
      agent: agent,
      project: first,
      context: second.chat,
      external_session_id: "wrong-project",
      prompt_count: 1,
      started_at: Time.current,
      last_used_at: Time.current
    )

    assert_not session.valid?
    assert_includes session.errors[:context], "must belong to the project"
  end
end
