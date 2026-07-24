class CreateTodoLists < ActiveRecord::Migration[8.1]
  def up
    create_table :todo_lists do |t|
      t.references :project, null: false
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_reference :todos, :todo_list

    execute <<~SQL
      INSERT INTO todo_lists (project_id, name, position, created_at, updated_at)
      SELECT DISTINCT project_id, 'Todos', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM todos
    SQL
    execute <<~SQL
      UPDATE todos SET todo_list_id = (SELECT id FROM todo_lists WHERE todo_lists.project_id = todos.project_id)
    SQL
  end

  def down
    remove_reference :todos, :todo_list
    drop_table :todo_lists
  end
end
