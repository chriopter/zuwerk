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
    queued = next_event
    @agent.messages.create!(project: @project, body: "Already answered", agent_event: @event)
    make_stale

    assert_equal :completed, watchdog.call

    assert @event.reload.delivered_at?
    assert_equal "completed", @event.state
    assert_equal @now, @event.finished_at
    assert_equal [ queued ], @enqueued
  end

  test "marks a correlated Board publication complete instead of prompting twice" do
    automation = BoardAutomation.create!(project: @project, creator: @human, agent: @agent, title: "Digest", cadence: "daily", prompt: "Publish")
    post = automation.run_now!
    board_event = post.agent_event
    post.publish!("Published Board result", event: board_event)
    board_event.update_columns(created_at: @now - 10.minutes, updated_at: @now - 10.minutes)

    assert_equal :completed, watchdog_for(board_event).call

    assert board_event.reload.delivered_at?
    assert_equal "completed", board_event.state
  end

  test "repairs working presence when delivery persisted before the bridge crashed" do
    queued = next_event
    @event.update!(delivered_at: @now - 1.minute)
    @agent.update!(working_status: true, working_label: "Still shown as working", heartbeat_at: @now - 30.seconds)

    assert_equal :completed, watchdog.call

    assert_equal "completed", @event.reload.state
    assert_equal @now, @event.finished_at
    assert_not @agent.reload.working_status?
    assert_nil @agent.working_label
    assert_nil @agent.heartbeat_at
    assert_equal [ queued ], @enqueued
  end

  test "makes retry exhaustion visible and does not enqueue again" do
    queued = next_event
    make_stale
    @event.update_columns(watchdog_attempts: 3, watchdog_retry_at: @now - 1.second)
    @agent.update!(working_status: true, working_label: "Stuck", heartbeat_at: @now - 10.minutes)

    assert_equal :failed, watchdog.call

    assert_equal [ queued ], @enqueued
    assert_match(/retry limit reached/, @event.reload.last_error)
    assert_equal "failed", @event.state
    assert_equal @now, @event.finished_at
    assert_nil @event.watchdog_retry_at
    assert_not @agent.reload.working_status?
  end

  test "retries the exact running event and ignores terminal events" do
    make_stale
    @event.transition_to!("running")
    @event.update_columns(updated_at: @now - 10.minutes)

    assert_equal :retried, watchdog.call
    assert_same @event, @enqueued.sole
    assert_equal "running", @event.reload.state

    %w[completed failed cancelled].each do |state|
      terminal = next_event
      terminal.update_columns(state: state, finished_at: @now, updated_at: @now - 10.minutes)
      @enqueued.clear
      assert_equal state.to_sym, watchdog_for(terminal).call
      assert_empty @enqueued
    end
  end

  private
    def make_stale
      @event.update_columns(created_at: @now - 10.minutes, updated_at: @now - 10.minutes)
    end

    def watchdog(runtime: FakeRuntime.new)
      watchdog_for(@event, runtime: runtime)
    end

    def watchdog_for(event, runtime: FakeRuntime.new)
      HostedAgents::EventWatchdog.new(
        event,
        clock: -> { @now },
        runtime_factory: ->(_hosted_agent) { runtime },
        enqueue: ->(event) { @enqueued << event }
      )
    end

    def next_event
      @project.messages.create!(author: @human, body: "@watch-agent next").agent_events.find_by!(recipient: @agent)
    end
end
