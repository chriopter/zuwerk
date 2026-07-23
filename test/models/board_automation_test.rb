require "test_helper"

class BoardAutomationTest < ActiveSupport::TestCase
  setup do
    @human = User.create!(name: "Board Owner", email: "board-owner@example.com", password: "password1")
    @agent = User.create!(name: "Board Agent", kind: :agent)
    @project = Project.create!(name: "Board Project")
  end

  test "requires a project agent title prompt and supported cadence" do
    automation = BoardAutomation.new(project: @project, creator: @human, agent: @human, title: "", cadence: "yearly", prompt: "")

    assert_not automation.valid?
    assert_includes automation.errors[:agent], "must be an agent"
    assert automation.errors[:title].any?
    assert automation.errors[:prompt].any?
    assert automation.errors[:cadence].any?
  end

  test "sets the first run from the selected cadence" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      automation = create_automation(cadence: "daily")

      assert_equal 1.day.from_now, automation.next_run_at
    end
  end

  test "changing cadence reschedules the next run" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      automation = create_automation(cadence: "weekly")

      automation.update!(cadence: "hourly")

      assert_equal 1.hour.from_now, automation.next_run_at
    end
  end

  test "resuming schedules the next future occurrence without backfill" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      automation = create_automation(cadence: "daily")
      automation.update!(active: false, next_run_at: 3.days.ago)

      automation.resume!

      assert automation.active?
      assert_equal 1.day.from_now, automation.next_run_at
    end
  end

  test "dispatches one due occurrence and advances beyond now" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      automation = create_automation(cadence: "hourly")
      automation.update!(next_run_at: 2.hours.ago)

      assert_difference [ -> { BoardPost.count }, -> { AgentEvent.where(event_type: "board_scheduled").count } ], 1 do
        automation.dispatch_due!
      end

      post = automation.board_posts.last
      event = post.agent_event
      assert_equal 2.hours.ago, post.scheduled_for
      assert_equal @agent, post.author
      assert_equal "Summarize the current project state.", post.prompt_snapshot
      assert_equal @agent, event.recipient
      assert_equal post, event.subject
      assert_equal "board", event.payload.dig(:context, :origin)
      assert_equal automation.id, event.payload.dig(:context, :board_automation, :id)
      assert_operator automation.reload.next_run_at, :>, Time.current

      assert_no_difference [ -> { BoardPost.count }, -> { AgentEvent.count } ] do
        automation.dispatch_due!
      end
    end
  end

  test "repairs a pre-existing occurrence collision and advances the schedule" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      automation = create_automation(cadence: "hourly")
      automation.update!(next_run_at: 1.hour.ago)
      existing = automation.board_posts.create!(author: @agent, title: automation.title, scheduled_for: automation.next_run_at, prompt_snapshot: "Snapshot")

      assert_equal existing, automation.dispatch_due!
      assert_operator automation.reload.next_run_at, :>, Time.current
      assert_equal 1, automation.board_posts.count
    end
  end

  test "queued occurrence keeps its original agent when automation changes" do
    automation = create_automation(cadence: "daily")
    post = automation.run_now!
    replacement = User.create!(name: "Replacement Board Agent", kind: :agent)

    automation.update!(agent: replacement)

    assert post.publish!("Original agent publication", event: post.agent_event)
    assert_equal @agent, post.reload.author
  end

  test "run now creates an occurrence without moving the recurring schedule" do
    travel_to Time.zone.local(2026, 7, 23, 10, 0) do
      automation = create_automation(cadence: "weekly")
      scheduled = automation.next_run_at

      post = automation.run_now!

      assert_equal Time.current, post.scheduled_for
      assert_equal scheduled, automation.reload.next_run_at
      assert_equal "board_scheduled", post.agent_event.event_type
    end
  end

  private

  def create_automation(cadence:)
    BoardAutomation.create!(
      project: @project,
      creator: @human,
      agent: @agent,
      title: "Weekly project digest",
      cadence: cadence,
      prompt: "Summarize the current project state."
    )
  end
end
