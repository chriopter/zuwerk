class AddConnectorOwnerToAgentEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_events, :connector_connection_id, :string
  end
end
