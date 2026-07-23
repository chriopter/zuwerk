class AddAutonomousToHostedAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :hosted_agents, :autonomous, :boolean, default: false, null: false
  end
end
