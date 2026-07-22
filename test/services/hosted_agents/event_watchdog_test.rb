require "test_helper"

class HostedAgents::EventWatchdogTest < ActiveSupport::TestCase
  class FakeRuntime
    attr_reader :provisions

    def initialize(running: true)
      @running = running
      @provisions = 0
    end

    def running? = @running

    def provision
      @provisions += 1
      @running = true
    end
  end

  setup do
    @now = Time.zone.parse("2026-07-22 18:00:00")
    @human = User.create!(name: "Watch Human", email: "watch-human@example.com", password: "password1")
    @agent = User.create!(name: "Watch Agent", kind: :agent)
    @hosted_agent = HostedAgent.create!(user: @agent, runtime: "codex", state: "running", bridge_connected_at: @now)
    @project = Project.create!(name: "Watchdog Project")
    @source = Message.create!(author: @human, project: @project, body: "@watch-agent do this")
    @event = @source.agent_events.find_by!(recipient: @agent)
    @enqueued = []
  end

  test "re-enqueues a stale event with backoff and repairs a stopped runtime only once" do
    runtime = FakeRuntime.new(running: false)
    make_stale
    @hosted_agent.update!(state: "error")

    assert_equal :retried, watchdog(runtime: runtime).call

    assert_equal [ @event ], @enqueued
    assert_equal 1, runtime.provisions
    assert_equal 1, @event.reload.watchdog_attempts
    assert_equal @now + 1.minute, @event.watchdog_retry_at
    assert_equal @now, @event.runtime_recovered_at

    @event.update_columns(updated_at: @now - 10.minutes, watchdog_retry_at: @now - 1.second)
    watchdog(runtime: runtime).call
    assert_equal 1, runtime.provisions
    assert_equal 2, @event.reload.watchdog_attempts
    assert_equal @now + 2.minutes, @event.watchdog_retry_at
  end

  test "leaves a live accepted event alone" do
    @event.update!(accepted_at: @now - 5.minutes)
    @agent.update!(working_status: true, working_label: "Working", heartbeat_at: @now - 30.seconds)

    assert_equal :running, watchdog.call

    assert_empty @enqueued
    assert_equal 0, @event.reload.watchdog_attempts
    assert @agent.reload.working_status?
  end

  test "marks a correlated publication complete instead of prompting twice" do
    @agent.messages.create!(project: @project, body: "Already answered", agent_event: @event)
    make_stale

    assert_equal :completed, watchdog.call

    assert @event.reload.delivered_at?
    assert_empty @enqueued
  end

  test "ignores an event that delivery already completed" do
    @event.update!(delivered_at: @now - 1.minute)

    assert_equal :completed, watchdog.call
    assert_empty @enqueued
  end

  test "makes retry exhaustion visible and does not enqueue again" do
    make_stale
    @event.update_columns(watchdog_attempts: 3, watchdog_retry_at: @now - 1.second)
    @agent.update!(working_status: true, working_label: "Stuck", heartbeat_at: @now - 10.minutes)

    assert_equal :failed, watchdog.call

    assert_empty @enqueued
    assert_match(/retry limit reached/, @event.reload.last_error)
    assert_nil @event.watchdog_retry_at
    assert_not @agent.reload.working_status?
  end

  private
    def make_stale
      @event.update_columns(created_at: @now - 10.minutes, updated_at: @now - 10.minutes)
    end

    def watchdog(runtime: FakeRuntime.new)
      HostedAgents::EventWatchdog.new(
        @event,
        clock: -> { @now },
        runtime_factory: ->(_hosted_agent) { runtime },
        enqueue: ->(event) { @enqueued << event }
      )
    end
end
