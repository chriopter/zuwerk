class CreateBoardAutomationsAndPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :board_automations do |t|
      t.references :project, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :cadence, null: false
      t.boolean :active, null: false, default: true
      t.datetime :next_run_at, null: false
      t.timestamps
    end
    add_index :board_automations, [ :active, :next_run_at ]

    create_table :board_posts do |t|
      t.references :board_automation, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :agent_event, foreign_key: true, index: { unique: true }
      t.string :title, null: false
      t.datetime :scheduled_for, null: false
      t.datetime :published_at
      t.timestamps
    end
    add_index :board_posts, [ :board_automation_id, :scheduled_for ], unique: true
    add_index :board_posts, :published_at
  end
end
