class AddConnectorPresenceToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :connector_connection_id, :string
    add_column :users, :connector_heartbeat_at, :datetime
    add_index :users, :connector_connection_id, unique: true
  end
end
