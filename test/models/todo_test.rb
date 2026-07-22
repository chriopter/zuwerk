require "test_helper"

class TodoTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Launch")
    @human = User.create!(name: "Ada", email: "ada@example.com", password: "password1")
  end

  test "todo belongs to one project and stores a rich description" do
    todo = Todo.create!(project: @project, creator: @human, title: "Prepare launch", description: "**Ready** for review")

    assert_equal @project, todo.project
    assert_equal @human, todo.creator
    assert todo.open?
    assert_includes todo.description.to_plain_text, "Ready"
  end

  test "todo title is required and status can be completed" do
    todo = Todo.new(project: @project, creator: @human)

    assert_not todo.valid?
    todo.update(title: "Prepare launch", status: :completed)
    assert todo.completed?
  end

  test "comments belong to the todo and store rich text" do
    todo = Todo.create!(project: @project, creator: @human, title: "Prepare launch")
    comment = todo.comments.create!(author: @human, body: "Looks <strong>good</strong>")

    assert_equal @human, comment.author
    assert_includes comment.body.to_plain_text, "Looks good"
  end

  test "empty comments are rejected" do
    todo = Todo.create!(project: @project, creator: @human, title: "Prepare launch")

    assert_not todo.comments.new(author: @human, body: "").valid?
  end
end
