require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "default project is stable and named Zuwerk" do
    project = Project.default

    assert_equal "Zuwerk", project.name
    assert_equal project, Project.default
  end

  test "project names are required and unique without regard to case" do
    Project.create!(name: "Client portal")

    duplicate = Project.new(name: "client PORTAL")
    assert_not duplicate.valid?
    assert duplicate.errors.added?(:name, :taken, value: "client PORTAL")
  end

  test "creating a project creates its default task list immediately" do
    project = Project.create!(name: "Ready chat")

    assert_equal [ "Tasks" ], project.task_lists.pluck(:name)
  end

  test "chat messages belong to a project" do
    project = Project.create!(name: "Launch")
    human = User.create!(name: "Ada", email: "ada@example.com", password: "password1")
    message = ChatMessage.create!(author: human, project: project, body: "Hello launch")

    assert_equal [ message ], project.chat_messages.to_a
  end

  test "chat messages require an explicit project" do
    human = User.create!(name: "Ada", email: "ada@example.com", password: "password1")

    message = ChatMessage.new(author: human, body: "Unscoped message")

    assert_not message.valid?
    assert message.errors.added?(:project, :blank)
  end
end
