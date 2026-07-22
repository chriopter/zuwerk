class CreateTodoAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :todo_assignments do |t|
      t.references :todo, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.references :assigner, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :todo_assignments, [ :todo_id, :agent_id ], unique: true
  end
end
