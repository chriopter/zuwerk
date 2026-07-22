class CreateAgentSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_subscriptions do |t|
      t.references :project, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :agent_subscriptions, [ :project_id, :agent_id ], unique: true
  end
end
