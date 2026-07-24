class RemoveInProgressTodoStatus < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE todos SET status = 0 WHERE status = 2"
  end

  def down; end
end
