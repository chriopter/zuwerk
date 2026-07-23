class CreateAgentTerminalPanes < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_terminal_panes do |t|
      t.references :project, null: false, foreign_key: true
      t.references :hosted_agent, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :tmux_window, null: false
      t.timestamps
    end

    add_index :agent_terminal_panes, :tmux_window, unique: true
  end
end
