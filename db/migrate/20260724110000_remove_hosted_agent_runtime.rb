class RemoveHostedAgentRuntime < ActiveRecord::Migration[8.1]
  def change
    drop_table :agent_terminal_panes, if_exists: true
    drop_table :hosted_agent_sessions, if_exists: true
    drop_table :hosted_agents, if_exists: true

    remove_index :agent_events, name: "index_agent_events_for_watchdog", if_exists: true
    remove_column :agent_events, :runtime_recovered_at, :datetime, if_exists: true
    remove_column :agent_events, :watchdog_attempts, :integer, if_exists: true
    remove_column :agent_events, :watchdog_retry_at, :datetime, if_exists: true
  end
end
