class AddChatBridgeToHostedAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :hosted_agents, :bridge_connected_at, :datetime
    add_column :hosted_agents, :bridge_last_error, :text
    add_reference :agent_events, :response_message, foreign_key: { to_table: :messages }

    create_table :hosted_agent_sessions do |t|
      t.references :hosted_agent, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :external_session_id, null: false
      t.timestamps

      t.index [ :hosted_agent_id, :project_id ], unique: true
    end
  end
end
