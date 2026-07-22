class RemoveLegacyMessageState < ActiveRecord::Migration[8.1]
  def change
    remove_column :messages, :state, :integer
  end
end
