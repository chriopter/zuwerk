class MakeHostedAgentSessionsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :hosted_agent_sessions, :origin_type, :string
    add_column :hosted_agent_sessions, :origin_id, :integer
    add_column :hosted_agent_sessions, :last_used_at, :datetime

    execute <<~SQL.squish
      UPDATE hosted_agent_sessions
      SET origin_type = 'Project', origin_id = project_id, last_used_at = updated_at
    SQL

    change_column_null :hosted_agent_sessions, :origin_type, false
    change_column_null :hosted_agent_sessions, :origin_id, false
    change_column_null :hosted_agent_sessions, :last_used_at, false
    remove_index :hosted_agent_sessions, name: :index_hosted_agent_sessions_on_hosted_agent_id_and_project_id
    remove_reference :hosted_agent_sessions, :project, foreign_key: true
    add_index :hosted_agent_sessions, [ :origin_type, :origin_id ]
    add_index :hosted_agent_sessions, [ :hosted_agent_id, :origin_type, :origin_id ], unique: true, name: :index_hosted_agent_sessions_on_agent_and_origin

    remove_reference :agent_events, :response_message, foreign_key: { to_table: :messages }
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "polymorphic session origins cannot be reduced safely to projects"
  end
end
