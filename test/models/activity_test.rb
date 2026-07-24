require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(name: "Owner", email: "owner@example.com", password: "password1")
    @collaborator = User.create!(name: "Collaborator", email: "collaborator@example.com", password: "password1")
    @observer = User.create!(name: "Observer", email: "observer@example.com", password: "password1")
    @agent = User.create!(name: "Reporter", kind: :agent)
    @project = Project.create!(name: "Activity Project")
  end

  test "chat updates notify earlier participants and register the new participant" do
    @project.chat.messages.create!(author: @owner, body: "I joined this chat.")

    assert_difference -> { @owner.inbox_items.count }, 1 do
      message = @project.chat.messages.create!(author: @collaborator, body: "A new chat update.")
      activity = message.activities.sole

      assert_equal @project.chat, activity.trackable
      assert_equal "chat_message_created", activity.activity_type
    end

    item = @owner.inbox_items.sole
    assert_equal @project.chat, item.trackable
    assert_equal @collaborator, item.latest_activity.actor
    assert @project.chat.participations.exists?(user: @collaborator)
    assert_empty @observer.inbox_items
  end

  test "task comments notify the task creator and collapse updates into one item" do
    task = @project.tasks.create!(creator: @owner, title: "Prepare launch")
    first = task.comments.create!(author: @collaborator, body: "First update")
    item = @owner.inbox_items.sole
    item.mark_read!

    second = task.comments.create!(author: @collaborator, body: "Second update")

    assert_equal 1, @owner.inbox_items.count
    assert_equal task, item.reload.trackable
    assert_equal second.activities.sole, item.latest_activity
    assert_nil item.read_at
    assert_operator task.reload.last_activity_at, :>=, first.created_at
  end

  test "a scheduled briefing result notifies its creator" do
    briefing = @project.briefings.create!(
      creator: @owner,
      agent: @agent,
      title: "Weekly report",
      frequency: "weekly",
      prompt: "Report progress"
    )
    comment = briefing.run_now!

    assert_no_difference -> { @owner.inbox_items.count } do
      assert_not comment.published_at?
    end

    assert_difference -> { @owner.inbox_items.count }, 1 do
      comment.publish!("Everything is on track.", event: comment.agent_event)
    end

    assert_equal briefing, @owner.inbox_items.sole.trackable
    assert_equal "briefing_comment_created", comment.activities.sole.activity_type
  end

  test "authors do not receive their own updates" do
    task = @project.tasks.create!(creator: @owner, title: "Private notes")

    task.comments.create!(author: @owner, body: "My own update")

    assert_empty @owner.inbox_items
  end
end
