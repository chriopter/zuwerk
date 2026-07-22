class CreateAgentApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_approvals do |t|
      t.references :agent_event, null: false, foreign_key: true
      t.json :request_id, null: false
      t.json :options, null: false, default: []
      t.json :details, null: false, default: {}
      t.string :state, null: false, default: "pending"
      t.json :selected_option_id
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.datetime :expired_at
      t.datetime :cancelled_at
      t.timestamps
    end
    add_index :agent_approvals, :agent_event_id, unique: true, where: "state = 'pending'", name: "index_agent_approvals_one_pending_per_event"
  end
end
