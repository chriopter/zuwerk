require "test_helper"

class AgentEventWorkStateTest < ActiveSupport::TestCase
  test "acknowledges a todo in its structured assignment context" do
    human = User.create!(name: "Work Human", email: "work-human@example.com", password: "password1")
    agent = User.create!(name: "Work Agent", kind: :agent)
    project = Project.create!(name: "Work State")
    todo = project.todos.create!(creator: human, title: "Ship the work state")
    event = todo.assignments.create!(agent: agent, assigner: human).agent_events.sole

    event.acknowledge!

    assert event.reload.active?
    assert_equal todo, event.todo
    assert_equal "👍", todo.reactions.find_by!(author: agent).emoji

    event.update!(delivered_at: Time.current)
    assert_not event.active?
  end
end
