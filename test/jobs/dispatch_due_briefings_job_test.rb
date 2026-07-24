require "test_helper"

class DispatchDueBriefingsJobTest < ActiveJob::TestCase
  test "dispatches every due active briefing once" do
    human = User.create!(name: "Scheduler Human", email: "scheduler-human@example.com", password: "password1")
    agent = User.create!(name: "Scheduler Agent", kind: :agent)
    project = Project.create!(name: "Scheduler Project")
    due = Briefing.create!(project: project, creator: human, agent: agent, title: "Due", frequency: "daily", prompt: "Publish")
    future = Briefing.create!(project: project, creator: human, agent: agent, title: "Future", frequency: "weekly", prompt: "Publish")
    paused = Briefing.create!(project: project, creator: human, agent: agent, title: "Paused", frequency: "hourly", prompt: "Publish", active: false)
    due.update!(next_run_at: 1.minute.ago)
    paused.update!(next_run_at: 1.minute.ago)

    assert_difference -> { due.comments.count }, 1 do
      assert_no_difference [ -> { future.comments.count }, -> { paused.comments.count } ] do
        DispatchDueBriefingsJob.perform_now
      end
    end
  end
end
