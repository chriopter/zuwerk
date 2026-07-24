require "test_helper"

class AgentApprovalTest < ActiveSupport::TestCase
  setup do
    @human = User.create!(name: "Approval Human", email: "approval-human@example.com", password: "password1")
    @agent = User.create!(name: "Approval Agent", kind: :agent)
    @event = AgentEvent.create!(recipient: @agent, subject: ChatMessage.create!(author: @human, project: Project.default, body: "Approval"), event_type: "chat_message_mentioned")
    @event.transition_to!("running")
    @approval = AgentApproval.create!(agent_event: @event, request_id: { "nested" => [ 1, "x" ] }, options: [ { "optionId" => "allow", "kind" => "allow_once" }, { "optionId" => "reject", "kind" => "reject_once" } ], details: { "tool" => "shell" })
  end

  test "persists exact arbitrary request IDs and bounded permission data" do
    assert_equal({ "nested" => [ 1, "x" ] }, @approval.reload.request_id)
    assert_equal %w[allow reject], @approval.options.map { |option| option.fetch("optionId") }
    assert_not AgentApproval.new(agent_event: @event, request_id: 1, options: [], details: { "x" => "a" * 70_000 }).valid?
  end

  test "accepts false as an exact JSON request ID" do
    @approval.expire!
    event = AgentEvent.create!(recipient: @agent, subject: ChatMessage.create!(author: @human, project: Project.default, body: "Another approval"), event_type: "chat_message_mentioned")
    event.transition_to!("running")

    approval = AgentApproval.create!(agent_event: event, request_id: false, options: [ { "optionId" => nil } ])
    assert_equal false, approval.reload.request_id
  end

  test "resolve accepts a listed option and is idempotent only for the same choice" do
    @approval.resolve!("allow", resolver: @human)
    assert_equal "resolved", @approval.reload.state
    assert_equal "allow", @approval.selected_option_id
    assert_equal @human, @approval.resolved_by
    assert_nothing_raised { @approval.resolve!("allow", resolver: @human) }
    assert_raises(AgentApproval::ResolutionError) { @approval.resolve!("reject", resolver: @human) }
  end

  test "preserves a numeric selected option ID without coercion" do
    @approval.update!(options: [ { "optionId" => 7 }, { "optionId" => "7" } ])

    @approval.resolve!(7, resolver: @human)

    assert_equal 7, @approval.reload.selected_option_id
    assert_nothing_raised { @approval.resolve!(7, resolver: @human) }
    assert_raises(AgentApproval::ResolutionError) { @approval.resolve!("7", resolver: @human) }
  end

  test "rejects invalid choices and agent resolvers" do
    assert_raises(AgentApproval::ResolutionError) { @approval.resolve!("missing", resolver: @human) }
    assert_raises(AgentApproval::ResolutionError) { @approval.resolve!("allow", resolver: @agent) }
  end

  test "only one pending approval can exist for an event" do
    duplicate = AgentApproval.new(agent_event: @event, request_id: "second", options: [ { "optionId" => "reject" } ])
    assert_not duplicate.valid?
  end

  test "expiry fails closed and cancels the event" do
    @approval.expire!
    assert_equal "expired", @approval.reload.state
    assert_equal "cancelled", @event.reload.state
  end
end
