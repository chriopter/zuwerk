class CreateChatTables < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email
      t.string :password_digest
      t.integer :kind, null: false, default: 0
      t.boolean :admin, null: false, default: false
      t.string :api_token_digest
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :api_token_digest, unique: true

    create_table :messages do |t|
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end

    create_table :reactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.string :emoji, null: false
      t.timestamps
    end
    add_index :reactions, %i[user_id message_id emoji], unique: true

    create_table :agent_invitations do |t|
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :redeemed_at
      t.timestamps
    end
    add_index :agent_invitations, :token_digest, unique: true
  end
end
