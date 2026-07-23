class CreateSearchDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :search_documents do |t|
      t.references :project, null: false, foreign_key: true
      t.string :source_type, null: false
      t.integer :source_id, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.string :url, null: false
      t.string :content_digest, null: false
      t.text :embedding, null: false
      t.datetime :source_created_at, null: false
      t.timestamps
    end

    add_index :search_documents, [ :project_id, :source_type, :source_id ], unique: true
  end
end
