require "test_helper"

class BoardFlowTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "Board Editor", email: "board-editor@example.com", password: "password1")
    @agent = User.create!(name: "Board Reporter", kind: :agent)
    @project = Project.create!(name: "Board Workspace")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "project overview opens a blog-like board with recurring automations" do
    get project_path(@project)
    assert_response :success
    assert_select "a[href='#{project_board_posts_path(@project)}']", text: /Briefing/

    get project_board_posts_path(@project)
    assert_response :success
    assert_select ".workspace-breadcrumb a[href='#{project_path(@project)}']", text: @project.name
    assert_select ".workspace-breadcrumb span[aria-current='page']", text: "Briefing"
    assert_select "h1", text: "Briefing", count: 1
    assert_select ".topbar-account-menu a[aria-current='page']", count: 0
    assert_select "a[href='#{new_project_board_automation_path(@project)}']", text: /New automation/
  end

  test "creates a recurring prompt for the selected agent and runs it now" do
    assert_difference -> { @project.board_automations.count }, 1 do
      post project_board_automations_path(@project), params: {
        board_automation: {
          title: "Monday briefing",
          cadence: "weekly",
          agent_id: @agent.id,
          prompt: "Review current work and publish the priorities."
        }
      }
    end

    automation = @project.board_automations.last
    assert_redirected_to project_board_automation_path(@project, automation)
    assert_equal @human, automation.creator
    assert_equal @agent, automation.agent
    assert_equal "Review current work and publish the priorities.", automation.prompt.to_plain_text

    assert_difference [ -> { automation.board_posts.count }, -> { AgentEvent.where(event_type: "board_post_scheduled").count } ], 1 do
      post run_now_project_board_automation_path(@project, automation)
    end
    assert_redirected_to project_board_automation_path(@project, automation)
  end

  test "renders only published posts and keeps project boundaries" do
    automation = create_automation(@project)
    published = automation.run_now!
    published.publish!("## Delivered\n\nUseful result", event: published.agent_event)
    automation.run_now!
    other_project = Project.create!(name: "Other Board Workspace")
    other = create_automation(other_project).run_now!
    other.publish!("Private elsewhere", event: other.agent_event)

    get project_board_posts_path(@project)
    assert_response :success
    assert_select "a[href='#{project_board_post_path(@project, published)}']", text: /Monday briefing/
    assert_select ".board-post-entry", count: 1
    assert_select ".board-post-entry", text: /Useful result/
    assert_select "body", text: /Private elsewhere/, count: 0

    get project_board_post_path(@project, published)
    assert_response :success
    assert_select ".board-post-body h2", text: "Delivered"

    get project_board_post_path(@project, other)
    assert_response :not_found
  end

  test "shows a failed run reason and retry action" do
    automation = create_automation(@project)
    post = automation.run_now!
    post.agent_event.update!(state: "failed", last_error: "Adapter unavailable", finished_at: Time.current)

    get project_board_automation_path(@project, automation)

    assert_response :success
    assert_select ".board-run-error", text: /Adapter unavailable/
    assert_select "form[action='#{run_now_project_board_automation_path(@project, automation)}'] button", text: "Retry now"
  end

  test "associates validation errors with their form fields" do
    post project_board_automations_path(@project), params: { board_automation: { title: "", cadence: "daily", agent_id: @agent.id, prompt: "" } }

    assert_response :unprocessable_entity
    assert_select "#board-form-errors[role='alert'][tabindex='-1']"
    assert_select "#board_automation_title[aria-invalid='true'][aria-describedby='board-title-error']"
    assert_select "#board-title-error"
    assert_select "lexxy-editor[aria-invalid='true'][aria-describedby*='board-prompt-error']"
  end

  test "allows any registered agent to own recurring work" do
    disconnected = User.create!(name: "Disconnected Board Agent", kind: :agent)

    assert_difference -> { @project.board_automations.count }, 1 do
      post project_board_automations_path(@project), params: { board_automation: { title: "Queued", cadence: "daily", agent_id: disconnected.id, prompt: "Publish" } }
    end

    assert_equal disconnected, @project.board_automations.last.agent
  end

  test "signed-out visitors cannot read or create board content" do
    delete session_path
    get project_board_posts_path(@project)
    assert_redirected_to new_session_path

    assert_no_difference -> { BoardAutomation.count } do
      post project_board_automations_path(@project), params: { board_automation: { title: "No", cadence: "daily", agent_id: @agent.id, prompt: "No" } }
    end
    assert_redirected_to new_session_path
  end

  private

  def create_automation(project)
    BoardAutomation.create!(project: project, creator: @human, agent: @agent, title: "Monday briefing", cadence: "weekly", prompt: "Publish")
  end
end
