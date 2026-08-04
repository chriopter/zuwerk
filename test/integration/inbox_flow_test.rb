require "test_helper"

class InboxFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(name: "Inbox Owner", email: "inbox-owner@example.com", password: "password1")
    @collaborator = User.create!(name: "Inbox Collaborator", email: "inbox-collaborator@example.com", password: "password1")
    @project = Project.create!(name: "Inbox Workspace")
    @task = @project.tasks.create!(creator: @owner, title: "Launch checklist")
    @comment = @task.comments.create!(author: @collaborator, body: "The checklist changed.")
    post session_path, params: { email: @owner.email, password: "password1" }
  end

  test "shows unread updates and marks a trackable read when opened" do
    item = @owner.inbox_items.sole

    get inbox_path

    assert_response :success
    assert_select "h1", text: "Inbox"
    assert_select ".inbox-row.is-unread", count: 1, text: /Launch checklist/
    assert_select "a[href='#{project_task_path(@project, @task, anchor: "task_comment_#{@comment.id}")}']"

    get project_task_path(@project, @task)

    assert_response :success
    assert item.reload.read?
  end

  test "filters by project and marks all visible items read" do
    other_project = Project.create!(name: "Other Inbox Workspace")
    other_task = other_project.tasks.create!(creator: @owner, title: "Other task")
    other_task.comments.create!(author: @collaborator, body: "Other update")

    get inbox_path(project_id: @project.id)
    assert_select ".inbox-row", count: 1, text: /Launch checklist/
    assert_select "body", text: /Other task/, count: 0

    patch mark_all_read_inbox_path, params: { project_id: @project.id }

    assert_redirected_to inbox_path(project_id: @project.id)
    assert @owner.inbox_items.find_by!(project: @project).read?
    assert_not @owner.inbox_items.find_by!(project: other_project).read?
  end

  test "shows project briefings as a second section" do
    agent = User.create!(name: "Inbox Reporter", kind: :agent)
    briefing = @project.briefings.create!(creator: @owner, agent: agent, title: "Weekly pulse", frequency: "weekly", prompt: "Report progress")

    get inbox_path(project_id: @project.id)

    assert_response :success
    assert_select ".updates-section", count: 2
    assert_select "#briefings a[href='#{project_briefing_path(@project, briefing)}']", text: /Weekly pulse/
    assert_select "a[href='#{new_project_briefing_path(@project)}']", minimum: 1
  end

  test "requires a signed-in human" do
    delete session_path

    get inbox_path

    assert_redirected_to new_session_path
  end
end
