class AddSharedFolderToHostedAgents < ActiveRecord::Migration[8.1]
  def up
    add_column :hosted_agents, :shared_folder, :boolean, default: false, null: false

    # Agents that are already hosted on this server are trusted workspace members,
    # so they keep working on the Zuwerk checkout itself.
    execute "UPDATE hosted_agents SET shared_folder = TRUE"
  end

  def down
    remove_column :hosted_agents, :shared_folder
  end
end
