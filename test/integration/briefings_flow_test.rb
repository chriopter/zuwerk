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
end
