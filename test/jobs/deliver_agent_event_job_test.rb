require "test_helper"

class DeliverAgentEventJobTest < ActiveJob::TestCase
  test "routes hosted deliveries to their dedicated serialized queue" do
    human = User.create!(name: "Queue Human", email: "queue-human@example.com", password: "password1")
    hosted_user = User.create!(name: "Hosted Queue Agent", kind: :agent)
    HostedAgent.create!(user: hosted_user, runtime: "claude", state: "running")
    external_user = User.create!(name: "External Queue Agent", kind: :agent)
    project = Project.create!(name: "Queue Project")
    message = Message.create!(author: human, project: project, body: "Queue this")

    hosted_event = AgentEvent.create!(recipient: hosted_user, subject: message, event_type: "mentioned")
    external_event = AgentEvent.create!(recipient: external_user, subject: message, event_type: "mentioned")

    assert_equal "hosted_agents", DeliverAgentEventJob.new(hosted_event).queue_name
    assert_equal "default", DeliverAgentEventJob.new(external_event).queue_name
  end
end
