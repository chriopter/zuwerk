class AddWatchdogStateToAgentEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_events, :watchdog_attempts, :integer, default: 0, null: false
    add_column :agent_events, :watchdog_retry_at, :datetime
    add_column :agent_events, :runtime_recovered_at, :datetime
    add_index :agent_events, [ :delivered_at, :watchdog_retry_at ], name: "index_agent_events_for_watchdog"
  end
end
