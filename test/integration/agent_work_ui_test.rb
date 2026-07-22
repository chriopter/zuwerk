require "test_helper"

class AgentWorkUiTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "UI Human", email: "ui-human@example.com", password: "password1")
    @agent = User.create!(name: "UI Agent", kind: :agent)
    @project = Project.create!(name: "Live UI")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "chat derives its compact turn strip from the latest concrete event state" do
    message = @project.messages.create!(author: @human, body: "@ui-agent work")
    event = message.agent_events.find_by!(recipient: @agent)

    get chat_project_path(@project)
    assert_select "#project_agent_turn_status [data-agent-event-id='#{event.public_id}']", text: /Queued/
    assert_select ".agent-turn-spinner", count: 0

    event.transition_to!("running")
    get chat_project_path(@project)
    assert_select "#project_agent_turn_status .agent-turn-spinner[role='status']", count: 1
    assert_select "[data-agent-event-id='#{event.public_id}']", text: /UI Agent is working/

    event.transition_to!("completed")
    get chat_project_path(@project)
    assert_select "#project_agent_turn_status [data-agent-event-id='#{event.public_id}']", count: 0
  end

  test "approval card is safely rendered at its chat origin without a spinner" do
    message = @project.messages.create!(author: @human, body: "@ui-agent deploy")
    event = message.agent_events.find_by!(recipient: @agent)
    event.transition_to!("running")
    approval = AgentApproval.create!(
      agent_event: event,
      request_id: "permission",
      details: { "tool" => "<script>alert(1)</script>", "title" => "Deploy", "description" => "Production" },
      options: [ { "optionId" => { "scope" => 7 }, "name" => "Allow once", "kind" => "allow_once" } ]
    )

    get chat_project_path(@project)

    assert_select "#project_agent_turn_status .agent-turn-spinner", count: 0
    assert_select "#agent_approval_#{approval.id}[role='alert']", text: /Deploy/
    assert_select "#agent_approval_#{approval.id} script", count: 0
    assert_select "form[action='#{agent_approval_path(approval)}'] input[name='option_index'][value='0']"
    assert_select "button[aria-label='Allow once for Deploy']", text: "Allow once"
  end

  test "todo detail and kanban show the same running event status" do
    todo = @project.todos.create!(creator: @human, title: "Ship it")
    assignment = todo.assignments.create!(agent: @agent, assigner: @human)
    event = assignment.agent_events.find_by!(recipient: @agent)
    event.transition_to!("running")

    get project_todo_path(@project, todo)
    assert_select "#todo_#{todo.id}_agent_status .agent-turn-spinner", count: 1

    get project_todos_path(@project)
    assert_select "#todo_#{todo.id}_kanban_agent_status [data-agent-event-id='#{event.public_id}'] .agent-turn-spinner", count: 1
  end
end
