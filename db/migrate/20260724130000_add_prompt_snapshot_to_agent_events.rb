class AddPromptSnapshotToAgentEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_events, :prompt_snapshot, :text
    add_column :agent_events, :prompted_at, :datetime
  end
end
