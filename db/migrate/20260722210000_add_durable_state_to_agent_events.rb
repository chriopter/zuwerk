class AddDurableStateToAgentEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :agent_events, :state, :string
    add_column :agent_events, :started_at, :datetime
    add_column :agent_events, :waiting_at, :datetime
    add_column :agent_events, :finished_at, :datetime
    execute <<~SQL.squish
      UPDATE agent_events SET state = CASE
        WHEN delivered_at IS NOT NULL THEN 'completed'
        WHEN last_error IS NOT NULL AND last_error != '' THEN 'failed'
        ELSE 'queued'
      END
    SQL
    change_column_default :agent_events, :state, from: nil, to: "queued"
    change_column_null :agent_events, :state, false
    add_index :agent_events, [ :recipient_id, :state, :created_at ], name: "index_agent_events_on_recipient_state_created"
  end

  def down
    remove_index :agent_events, name: "index_agent_events_on_recipient_state_created"
    remove_columns :agent_events, :state, :started_at, :waiting_at, :finished_at
  end
end
