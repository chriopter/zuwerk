class AddProjectsToChat < ActiveRecord::Migration[8.1]
  def up
    create_table :projects do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :projects, "lower(name)", unique: true, name: "index_projects_on_lower_name"

    add_reference :messages, :project, foreign_key: true
    add_reference :room_settings, :project, foreign_key: true

    now = connection.quote(Time.current)
    execute <<~SQL.squish
      INSERT INTO projects (name, created_at, updated_at)
      VALUES ('Zuwerk', #{now}, #{now})
    SQL
    default_project_id = select_value("SELECT id FROM projects WHERE name = 'Zuwerk'")
    execute "UPDATE messages SET project_id = #{connection.quote(default_project_id)} WHERE project_id IS NULL"
    execute "UPDATE room_settings SET project_id = #{connection.quote(default_project_id)} WHERE project_id IS NULL"

    change_column_null :messages, :project_id, false
    change_column_null :room_settings, :project_id, false
    remove_index :room_settings, :room_key
    remove_column :room_settings, :room_key
    remove_index :room_settings, :project_id
    add_index :room_settings, :project_id, unique: true
  end

  def down
    add_column :room_settings, :room_key, :string
    execute "UPDATE room_settings SET room_key = 'shared-' || id"
    change_column_null :room_settings, :room_key, false
    add_index :room_settings, :room_key, unique: true

    remove_index :room_settings, :project_id
    remove_reference :room_settings, :project, foreign_key: true
    remove_reference :messages, :project, foreign_key: true
    drop_table :projects
  end
end
