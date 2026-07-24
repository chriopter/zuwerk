class RenameChatSettingsAndSubscriptions < ActiveRecord::Migration[8.1]
  def change
    rename_table :room_settings, :chat_settings
    rename_table :agent_subscriptions, :chat_subscriptions
  end
end
