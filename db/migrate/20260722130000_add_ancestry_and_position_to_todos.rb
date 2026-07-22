class AddAncestryAndPositionToTodos < ActiveRecord::Migration[8.1]
  def change
    add_column :todos, :ancestry, :string
    add_column :todos, :position, :integer, null: false, default: 0
    add_index :todos, :ancestry
    add_index :todos, [ :project_id, :ancestry, :position ]
  end
end
