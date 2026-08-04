class AddAccountsAndMemberships < ActiveRecord::Migration[8.1]
  def up
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :account_number, null: false
      t.timestamps
    end
    add_index :accounts, :account_number, unique: true

    create_table :memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 1
      t.timestamps
    end
    add_index :memberships, %i[account_id user_id], unique: true

    add_reference :projects, :account, foreign_key: true
    add_reference :agent_invitations, :account, foreign_key: true

    account_number = format("%08d", SecureRandom.random_number(100_000_000))
    execute <<~SQL
      INSERT INTO accounts (name, account_number, created_at, updated_at)
      VALUES ('Zuwerk', '#{account_number}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    account_id = select_value("SELECT id FROM accounts LIMIT 1")
    execute "UPDATE projects SET account_id = #{account_id}"
    execute "UPDATE agent_invitations SET account_id = #{account_id}"
    execute <<~SQL
      INSERT INTO memberships (account_id, user_id, role, created_at, updated_at)
      SELECT #{account_id}, id, CASE WHEN kind = 0 THEN 0 ELSE 1 END, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM users
    SQL

    change_column_null :projects, :account_id, false
    change_column_null :agent_invitations, :account_id, false
    remove_index :projects, :name if index_exists?(:projects, :name)
    add_index :projects, %i[account_id name], unique: true
  end

  def down
    remove_index :projects, %i[account_id name]
    add_index :projects, :name, unique: true
    remove_reference :agent_invitations, :account, foreign_key: true
    remove_reference :projects, :account, foreign_key: true
    drop_table :memberships
    drop_table :accounts
  end
end
