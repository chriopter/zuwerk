class AddChatUpgrade < ActiveRecord::Migration[8.1]
  def change
    create_table :room_settings do |t|
      t.string :room_key, null: false, default: "shared"
      t.boolean :notify_agents, null: false, default: false
      t.timestamps
    end
    add_index :room_settings, :room_key, unique: true

    add_column :users, :working_status, :boolean, null: false, default: false
    add_column :users, :working_label, :string
    add_column :users, :heartbeat_at, :datetime

    add_column :messages, :state, :integer, null: false, default: 0
  end
end
