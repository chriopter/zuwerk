class CreateHostedAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :hosted_agents do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :runtime, null: false
      t.string :state, null: false, default: "stopped"
      t.string :container_id
      t.text :last_error
      t.datetime :last_started_at
      t.datetime :last_stopped_at

      t.timestamps
    end
  end
end
