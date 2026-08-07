class ReplaceProjectFilesWithLibraryPages < ActiveRecord::Migration[8.1]
  class MigrationLibraryPage < ActiveRecord::Base
    self.table_name = "library_pages"
  end

  class MigrationLibraryPageFile < ActiveRecord::Base
    self.table_name = "library_page_files"
  end

  def up
    create_table :library_pages do |t|
      t.references :project, null: false, foreign_key: true
      t.references :creator, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :ancestry
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :library_pages, :ancestry
    add_index :library_pages, [ :project_id, :ancestry, :position ]

    create_table :library_page_files do |t|
      t.references :library_page, null: false, foreign_key: true
      t.references :creator, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.timestamps
    end

    MigrationLibraryPage.reset_column_information
    MigrationLibraryPageFile.reset_column_information
    migrate_file_tree if table_exists?(:project_file_entries)
    drop_table :project_file_entries
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "The legacy folder model cannot be restored without losing page content."
  end

  private
    def migrate_file_tree
      select_all("SELECT id FROM projects ORDER BY id").each do |project|
        root = MigrationLibraryPage.create!(project_id: project["id"], title: "Home", position: 0)
        migrate_folder_children(project["id"], nil, root)
        migrate_files(project["id"], nil, root)
      end
    end

    def migrate_folder_children(project_id, legacy_parent_id, page_parent)
      legacy_entries(project_id, legacy_parent_id, "folder").each_with_index do |folder, position|
        page = MigrationLibraryPage.create!(
          project_id: project_id,
          creator_id: folder["creator_id"],
          title: folder["name"],
          ancestry: [ page_parent.ancestry, page_parent.id ].compact.join("/"),
          position: position
        )
        migrate_folder_children(project_id, folder["id"], page)
        migrate_files(project_id, folder["id"], page)
      end
    end

    def migrate_files(project_id, legacy_parent_id, page)
      legacy_entries(project_id, legacy_parent_id, "file").each do |file|
        page_file = MigrationLibraryPageFile.create!(library_page_id: page.id, creator_id: file["creator_id"], name: file["name"])
        execute <<~SQL.squish
          UPDATE active_storage_attachments
          SET record_type = 'LibraryPageFile', record_id = #{connection.quote(page_file.id)}
          WHERE record_type = 'ProjectFileEntry' AND record_id = #{connection.quote(file["id"])}
        SQL
      end
    end

    def legacy_entries(project_id, parent_id, kind)
      parent_clause = parent_id ? "parent_id = #{connection.quote(parent_id)}" : "parent_id IS NULL"
      select_all(<<~SQL.squish)
        SELECT id, creator_id, name
        FROM project_file_entries
        WHERE project_id = #{connection.quote(project_id)} AND #{parent_clause} AND kind = #{connection.quote(kind)}
        ORDER BY name_key, id
      SQL
    end
end
