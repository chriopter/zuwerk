class AddAcceptedAtToAgentEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_events, :accepted_at, :datetime
    add_index :agent_events, [ :recipient_id, :accepted_at ]
  end
end
