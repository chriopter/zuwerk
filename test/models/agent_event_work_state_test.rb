require "test_helper"

class AgentEventWorkStateTest < ActiveSupport::TestCase
  test "acknowledges a task in its structured assignment context" do
    human = User.create!(name: "Work Human", email: "work-human@example.com", password: "password1")
    agent = User.create!(name: "Work Agent", kind: :agent)
    project = Project.create!(name: "Work State")
    task = project.tasks.create!(creator: human, title: "Ship the work state")
    event = task.assignments.create!(agent: agent, assigned_by: human).agent_events.sole

    event.acknowledge!

    assert event.reload.active?
    assert_equal task, event.task
    assert_equal "👍", task.reactions.find_by!(author: agent).emoji

    event.update!(delivered_at: Time.current)
    assert_not event.active?
  end
end
