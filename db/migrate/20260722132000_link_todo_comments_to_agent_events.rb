class LinkTodoCommentsToAgentEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :todo_comments, :agent_event, foreign_key: true, index: { unique: true }
  end
end
