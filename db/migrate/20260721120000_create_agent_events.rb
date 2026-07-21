class CreateAgentEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_events do |t|
      t.string :public_id, null: false
      t.string :event_type, null: false
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :subject, polymorphic: true, null: false
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.datetime :delivered_at
      t.timestamps
    end

    add_index :agent_events, :public_id, unique: true
    add_index :agent_events, [ :event_type, :recipient_id, :subject_type, :subject_id ],
      unique: true, name: "index_agent_events_on_unique_delivery"
  end
end
