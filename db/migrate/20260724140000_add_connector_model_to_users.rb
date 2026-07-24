class AddConnectorModelToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :connector_model, :string
  end
end
