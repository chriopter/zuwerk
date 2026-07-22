class MakeReactionsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    rename_column :reactions, :user_id, :author_id
    add_column :reactions, :reactable_type, :string
    add_column :reactions, :reactable_id, :integer

    execute <<~SQL
      UPDATE reactions
      SET reactable_type = 'Message', reactable_id = message_id
    SQL

    change_column_null :reactions, :reactable_type, false
    change_column_null :reactions, :reactable_id, false
    remove_index :reactions, column: %i[author_id message_id emoji]
    remove_reference :reactions, :message, foreign_key: true
    add_index :reactions, %i[reactable_type reactable_id]
    add_index :reactions, %i[author_id reactable_type reactable_id emoji], unique: true, name: :index_reactions_on_author_reactable_emoji
  end

  def down
    add_reference :reactions, :message, foreign_key: true
    execute <<~SQL
      UPDATE reactions
      SET message_id = reactable_id
      WHERE reactable_type = 'Message'
    SQL
    execute "DELETE FROM reactions WHERE message_id IS NULL"
    change_column_null :reactions, :message_id, false
    remove_index :reactions, name: :index_reactions_on_author_reactable_emoji
    remove_index :reactions, column: %i[reactable_type reactable_id]
    remove_column :reactions, :reactable_type
    remove_column :reactions, :reactable_id
    rename_column :reactions, :author_id, :user_id
    add_index :reactions, %i[user_id message_id emoji], unique: true
  end
end
