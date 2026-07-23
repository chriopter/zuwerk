class CreateProjectFileEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :project_file_entries do |t|
      t.references :project, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.references :parent, foreign_key: { to_table: :project_file_entries }
      t.string :kind, null: false
      t.string :name, null: false
      t.string :name_key, null: false
      t.timestamps
    end

    add_index :project_file_entries, [ :project_id, :parent_id, :name_key ], unique: true, name: "index_file_entries_on_project_parent_name", where: "parent_id IS NOT NULL"
    add_index :project_file_entries, [ :project_id, :name_key ], unique: true, name: "index_root_file_entries_on_project_name", where: "parent_id IS NULL"
  end
end
