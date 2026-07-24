require "test_helper"

class BriefingTest < ActiveSupport::TestCase
  setup do
    @human = User.create!(name: "Briefing Owner", email: "briefing-owner@example.com", password: "password1")
    @agent = User.create!(name: "Briefing Agent", kind: :agent)
    @project = Project.create!(name: "Briefing Project")
  end

  test "requires an agent title prompt and supported frequency" do
    briefing = Briefing.new(project: @project, creator: @human, agent: @human, title: "", frequency: "yearly", prompt: "")

    assert_not briefing.valid?
    assert_includes briefing.errors[:agent], "must be an agent"
    assert briefing.errors[:title].any?
    assert briefing.errors[:prompt].any?
    assert briefing.errors[:frequency].any?
  end

  test "sets the first run from the selected frequency" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      briefing = create_briefing(frequency: "daily")

      assert_equal 1.day.from_now, briefing.next_run_at
      assert_equal Time.current, briefing.last_activity_at
    end
  end

  test "changing frequency reschedules the next run" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      briefing = create_briefing(frequency: "weekly")

      briefing.update!(frequency: "hourly")

      assert_equal 1.hour.from_now, briefing.next_run_at
    end
  end

  test "dispatches one due agent comment and advances beyond now" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      briefing = create_briefing(frequency: "hourly")
      briefing.update!(next_run_at: 2.hours.ago)

      assert_difference [ -> { BriefingComment.count }, -> { AgentEvent.where(event_type: "briefing_scheduled").count } ], 1 do
        briefing.dispatch_due!
      end

      comment = briefing.comments.last
      event = comment.agent_event
      assert_equal 2.hours.ago, comment.scheduled_for
      assert_equal @agent, comment.author
      assert_equal "Summarize the current project state.", comment.prompt_snapshot
      assert_equal comment, event.subject
      assert_equal "briefing", event.payload.dig(:context, :origin)
      assert_equal briefing.id, event.payload.dig(:context, :briefing, :id)
      assert_operator briefing.reload.next_run_at, :>, Time.current

      assert_no_difference [ -> { BriefingComment.count }, -> { AgentEvent.count } ] do
        briefing.dispatch_due!
      end
    end
  end

  test "publishing a comment moves the briefing to the latest activity" do
    briefing = create_briefing(frequency: "daily")
    older = create_briefing(frequency: "weekly", title: "Older")
    older.update_column(:last_activity_at, 2.days.ago)
    comment = older.run_now!

    travel 1.minute do
      comment.publish!("Current update", event: comment.agent_event)
      assert_equal comment.activities.sole.created_at, older.reload.last_activity_at
      assert_equal older, @project.briefings.recently_active.first
    end
  end

  test "human comments share the same activity stream" do
    briefing = create_briefing(frequency: "daily")
    comment = briefing.comments.create!(author: @human, body: "A follow-up", published_at: Time.current)

    assert_equal "A follow-up", comment.body.to_plain_text
    assert_nil comment.scheduled_for
    assert_equal comment.activities.sole.created_at, briefing.reload.last_activity_at
  end

  test "run now does not move the recurring schedule" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      briefing = create_briefing(frequency: "weekly")
      scheduled = briefing.next_run_at

      comment = briefing.run_now!

      assert_equal Time.current, comment.scheduled_for
      assert_equal scheduled, briefing.reload.next_run_at
      assert_equal "briefing_scheduled", comment.agent_event.event_type
    end
  end

  private

  def create_briefing(frequency:, title: "Weekly project digest")
    Briefing.create!(
      project: @project,
      creator: @human,
      agent: @agent,
      title: title,
      frequency: frequency,
      prompt: "Summarize the current project state."
    )
  end
end
