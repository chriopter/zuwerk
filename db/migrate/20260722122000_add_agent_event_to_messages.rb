class AddAgentEventToMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :messages, :agent_event, foreign_key: true, index: { unique: true }
  end
end
