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

  test "creating a project creates its single room setting immediately" do
    project = Project.create!(name: "Ready chat")

    assert_equal project, RoomSetting.find_by!(project_id: project.id).project
  end

  test "messages and the single room setting belong to a project" do
    project = Project.create!(name: "Launch")
    human = User.create!(name: "Ada", email: "ada@example.com", password: "password1")
    message = Message.create!(author: human, project: project, body: "Hello launch")

    assert_equal [ message ], project.messages.to_a
    assert_equal project, project.room_setting.project
    assert_equal project.room_setting, project.room_setting
  end

  test "messages without an explicit project use the default project" do
    human = User.create!(name: "Ada", email: "ada@example.com", password: "password1")

    message = Message.create!(author: human, body: "Legacy-compatible message")

    assert_equal Project.default, message.project
  end
end
