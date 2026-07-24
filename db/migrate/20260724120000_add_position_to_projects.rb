class AddPositionToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :position, :integer, default: 0, null: false
    execute <<~SQL
      UPDATE projects SET position = (
        SELECT COUNT(*) FROM projects AS ordered WHERE LOWER(ordered.name) < LOWER(projects.name)
      )
    SQL
  end

  def down
    remove_column :projects, :position
  end
end
