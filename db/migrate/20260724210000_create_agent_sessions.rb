class CreateAgentSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_sessions do |t|
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.references :project, null: false, foreign_key: true
      t.references :context, polymorphic: true, null: false
      t.string :external_session_id, null: false
      t.integer :prompt_count, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :last_used_at, null: false
      t.timestamps
    end

    add_index :agent_sessions, [ :agent_id, :context_type, :context_id ], unique: true
    add_index :agent_sessions, [ :agent_id, :last_used_at ]
  end
end
