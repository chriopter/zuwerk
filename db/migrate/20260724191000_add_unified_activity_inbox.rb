class AddUnifiedActivityInbox < ActiveRecord::Migration[8.1]
  def up
    create_table :chats do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.datetime :last_activity_at, null: false
      t.timestamps
    end

    execute <<~SQL
      INSERT INTO chats (project_id, last_activity_at, created_at, updated_at)
      SELECT projects.id,
             COALESCE(MAX(chat_messages.created_at), projects.created_at),
             projects.created_at,
             projects.updated_at
      FROM projects
      LEFT JOIN chat_messages ON chat_messages.project_id = projects.id
      GROUP BY projects.id
    SQL

    add_reference :chat_messages, :chat, foreign_key: true
    execute <<~SQL
      UPDATE chat_messages
      SET chat_id = (SELECT chats.id FROM chats WHERE chats.project_id = chat_messages.project_id)
    SQL
    change_column_null :chat_messages, :chat_id, false
    remove_reference :chat_messages, :project, foreign_key: true

    add_reference :chat_subscriptions, :chat, foreign_key: true
    execute <<~SQL
      UPDATE chat_subscriptions
      SET chat_id = (SELECT chats.id FROM chats WHERE chats.project_id = chat_subscriptions.project_id)
    SQL
    change_column_null :chat_subscriptions, :chat_id, false
    remove_index :chat_subscriptions, [ :project_id, :agent_id ]
    remove_reference :chat_subscriptions, :project, foreign_key: true
    add_index :chat_subscriptions, [ :chat_id, :agent_id ], unique: true

    add_column :tasks, :last_activity_at, :datetime
    execute <<~SQL
      UPDATE tasks
      SET last_activity_at = COALESCE(
        (SELECT MAX(task_comments.created_at) FROM task_comments WHERE task_comments.task_id = tasks.id),
        tasks.updated_at
      )
    SQL
    change_column_null :tasks, :last_activity_at, false
    add_index :tasks, [ :project_id, :last_activity_at ]

    rename_column :briefings, :activity_at, :last_activity_at

    create_table :activities do |t|
      t.references :project, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :trackable, polymorphic: true, null: false
      t.references :subject, polymorphic: true, null: false
      t.string :activity_type, null: false
      t.text :summary, null: false
      t.timestamps
    end
    add_index :activities, [ :project_id, :created_at ]

    create_table :participations do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :trackable, polymorphic: true, null: false
      t.timestamps
    end
    add_index :participations, [ :user_id, :trackable_type, :trackable_id ], unique: true, name: "index_participations_on_user_and_trackable"
    add_index :participations, [ :project_id, :user_id ]

    create_table :inbox_items do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :trackable, polymorphic: true, null: false
      t.references :latest_activity, null: false, foreign_key: { to_table: :activities }
      t.datetime :read_at
      t.timestamps
    end
    add_index :inbox_items, [ :user_id, :trackable_type, :trackable_id ], unique: true, name: "index_inbox_items_on_user_and_trackable"
    add_index :inbox_items, [ :user_id, :read_at, :updated_at ]

    backfill_participations
  end

  def down
    drop_table :inbox_items
    drop_table :participations
    drop_table :activities

    rename_column :briefings, :last_activity_at, :activity_at
    remove_index :tasks, [ :project_id, :last_activity_at ]
    remove_column :tasks, :last_activity_at

    add_reference :chat_subscriptions, :project, foreign_key: true
    execute <<~SQL
      UPDATE chat_subscriptions
      SET project_id = (SELECT chats.project_id FROM chats WHERE chats.id = chat_subscriptions.chat_id)
    SQL
    change_column_null :chat_subscriptions, :project_id, false
    remove_index :chat_subscriptions, [ :chat_id, :agent_id ]
    remove_reference :chat_subscriptions, :chat, foreign_key: true
    add_index :chat_subscriptions, [ :project_id, :agent_id ], unique: true

    add_reference :chat_messages, :project, foreign_key: true
    execute <<~SQL
      UPDATE chat_messages
      SET project_id = (SELECT chats.project_id FROM chats WHERE chats.id = chat_messages.chat_id)
    SQL
    change_column_null :chat_messages, :project_id, false
    remove_reference :chat_messages, :chat, foreign_key: true

    drop_table :chats
  end

  private

  def backfill_participations
    execute <<~SQL
      INSERT OR IGNORE INTO participations
        (project_id, user_id, trackable_type, trackable_id, created_at, updated_at)
      SELECT chats.project_id, chat_messages.author_id, 'Chat', chats.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM chat_messages
      INNER JOIN chats ON chats.id = chat_messages.chat_id
    SQL
    execute <<~SQL
      INSERT OR IGNORE INTO participations
        (project_id, user_id, trackable_type, trackable_id, created_at, updated_at)
      SELECT tasks.project_id, tasks.creator_id, 'Task', tasks.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM tasks
    SQL
    execute <<~SQL
      INSERT OR IGNORE INTO participations
        (project_id, user_id, trackable_type, trackable_id, created_at, updated_at)
      SELECT tasks.project_id, task_comments.author_id, 'Task', tasks.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM task_comments
      INNER JOIN tasks ON tasks.id = task_comments.task_id
    SQL
    execute <<~SQL
      INSERT OR IGNORE INTO participations
        (project_id, user_id, trackable_type, trackable_id, created_at, updated_at)
      SELECT briefings.project_id, briefings.creator_id, 'Briefing', briefings.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM briefings
    SQL
    execute <<~SQL
      INSERT OR IGNORE INTO participations
        (project_id, user_id, trackable_type, trackable_id, created_at, updated_at)
      SELECT briefings.project_id, briefing_comments.author_id, 'Briefing', briefings.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM briefing_comments
      INNER JOIN briefings ON briefings.id = briefing_comments.briefing_id
      WHERE briefing_comments.published_at IS NOT NULL
    SQL
  end
end
