require "test_helper"

class BriefingsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Briefing Editor", email: "briefing-editor@example.com", password: "password1")
    @agent = User.create!(name: "Briefing Reporter", kind: :agent)
    @project = Project.create!(name: "Briefing Workspace")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "lists briefings by their latest comment" do
    older = create_briefing("Older")
    newer = create_briefing("Newer")
    older.comments.create!(author: @human, body: "Newest comment", published_at: 1.minute.from_now)

    get project_briefings_path(@project)

    assert_response :success
    assert_select "h1", text: "Briefings"
    assert_select ".briefing-row" do |rows|
      assert_includes rows.first.text, older.title
      assert_includes rows.last.text, newer.title
    end
  end

  test "creates a recurring briefing and queues an immediate run" do
    assert_difference -> { @project.briefings.count }, 1 do
      post project_briefings_path(@project), params: {
        briefing: {
          title: "Monday briefing",
          frequency: "weekly",
          agent_id: @agent.id,
          prompt: "Review current work and report the priorities."
        }
      }
    end

    briefing = @project.briefings.last
    assert_redirected_to project_briefing_path(@project, briefing)
    assert_equal @human, briefing.creator
    assert_equal @agent, briefing.agent

    assert_difference [ -> { briefing.comments.count }, -> { AgentEvent.where(event_type: "briefing_scheduled").count } ], 1 do
      post run_now_project_briefing_path(@project, briefing)
    end
  end

  test "adds edits and deletes human comments" do
    briefing = create_briefing

    assert_difference -> { briefing.comments.published.count }, 1 do
      post project_briefing_comments_path(@project, briefing), params: { briefing_comment: { body: "Initial context" } }
    end
    comment = briefing.comments.published.last
    assert_redirected_to project_briefing_path(@project, briefing, anchor: "briefing_comment_#{comment.id}")

    patch project_briefing_comment_path(@project, briefing, comment), params: { briefing_comment: { body: "Updated context" } }
    assert_equal "Updated context", comment.reload.body.to_plain_text

    assert_difference -> { briefing.comments.count }, -1 do
      delete project_briefing_comment_path(@project, briefing, comment)
    end
  end

  test "mentions an agent from a briefing comment" do
    briefing = create_briefing

    assert_difference -> { AgentEvent.where(event_type: "briefing_comment_mentioned").count }, 1 do
      post project_briefing_comments_path(@project, briefing), params: { briefing_comment: { body: "Please check this, @#{@agent.handle}." } }
    end

    event = briefing.comments.published.last.agent_events.sole
    assert_equal @agent, event.recipient
    assert_equal "queued", event.state
  end

  test "shows the assigned agent avatar" do
    briefing = create_briefing

    get project_briefing_path(@project, briefing)

    assert_response :success
    assert_select ".briefing-actions .avatar-stack-item[data-agent-id='#{@agent.id}']", text: @agent.name.first
  end

  test "pins the latest completed briefing result above the update feed" do
    briefing = create_briefing
    older = create_result(briefing, "Older report", 2.days.ago)
    latest = create_result(briefing, "Latest report", 1.day.ago)
    briefing.comments.create!(author: @agent, body: "A later conversational reply", published_at: Time.current)

    get project_briefing_path(@project, briefing)

    assert_response :success
    assert_select ".briefing-pinned-result", count: 1 do
      assert_select ".briefing-pinned-body", text: /Latest report/
      assert_select ".briefing-pinned-body", text: /Older report/, count: 0
      assert_select ".briefing-pinned-body", text: /conversational reply/, count: 0
      assert_select "a[href='##{dom_id(latest)}']", text: /View in updates/
    end
    assert_select "##{dom_id(older)}", count: 1
    assert_select "##{dom_id(latest)}", count: 1
  end

  test "keeps briefings inside their project" do
    briefing = create_briefing
    other_project = Project.create!(name: "Other Briefing Workspace")

    get project_briefing_path(other_project, briefing)

    assert_response :not_found
  end

  test "signed-out visitors cannot read or create briefings" do
    delete session_path
    get project_briefings_path(@project)
    assert_redirected_to new_session_path

    assert_no_difference -> { Briefing.count } do
      post project_briefings_path(@project), params: { briefing: { title: "No", frequency: "daily", agent_id: @agent.id, prompt: "No" } }
    end
    assert_redirected_to new_session_path
  end

  private

  def create_briefing(title = "Monday briefing")
    Briefing.create!(project: @project, creator: @human, agent: @agent, title: title, frequency: "weekly", prompt: "Publish")
  end

  def create_result(briefing, body, scheduled_for)
    briefing.comments.create!(
      author: @agent,
      title: briefing.title,
      body: body,
      prompt_snapshot: briefing.prompt.to_plain_text,
      scheduled_for: scheduled_for,
      published_at: scheduled_for
    )
  end
end
