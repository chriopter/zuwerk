require "test_helper"

class DispatchDueBoardAutomationsJobTest < ActiveJob::TestCase
  test "dispatches every due active automation once" do
    human = User.create!(name: "Scheduler Human", email: "scheduler-human@example.com", password: "password1")
    agent = User.create!(name: "Scheduler Agent", kind: :agent)
    project = Project.create!(name: "Scheduler Project")
    due = BoardAutomation.create!(project: project, creator: human, agent: agent, title: "Due", cadence: "daily", prompt: "Publish")
    future = BoardAutomation.create!(project: project, creator: human, agent: agent, title: "Future", cadence: "weekly", prompt: "Publish")
    paused = BoardAutomation.create!(project: project, creator: human, agent: agent, title: "Paused", cadence: "hourly", prompt: "Publish", active: false)
    due.update!(next_run_at: 1.minute.ago)
    paused.update!(next_run_at: 1.minute.ago)

    assert_difference -> { due.board_posts.count }, 1 do
      assert_no_difference [ -> { future.board_posts.count }, -> { paused.board_posts.count } ] do
        DispatchDueBoardAutomationsJob.perform_now
      end
    end
  end
end
