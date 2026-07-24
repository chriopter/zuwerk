class EnforceTaskStructure < ActiveRecord::Migration[8.1]
  def change
    drop_table :chat_settings do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.boolean :notify_agents, default: false, null: false
      t.timestamps
    end

    add_foreign_key :task_lists, :projects
    add_foreign_key :tasks, :task_lists
    add_index :task_lists, [ :project_id, :name ], unique: true
    add_index :task_lists, [ :project_id, :position ]
    add_index :tasks, [ :task_list_id, :ancestry, :position ]
  end
end
