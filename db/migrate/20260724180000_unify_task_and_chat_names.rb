class UnifyTaskAndChatNames < ActiveRecord::Migration[8.1]
  def up
    rename_table :messages, :chat_messages
    rename_table :todo_lists, :task_lists
    rename_table :todos, :tasks
    rename_table :todo_comments, :task_comments
    rename_table :todo_assignments, :task_assignments

    rename_column :tasks, :todo_list_id, :task_list_id
    rename_column :task_comments, :todo_id, :task_id
    rename_column :task_assignments, :todo_id, :task_id
    rename_column :task_assignments, :assigner_id, :assigned_by_id

    execute "UPDATE task_lists SET name = 'Tasks' WHERE name = 'Todos'"
    execute <<~SQL
      INSERT INTO task_lists (project_id, name, position, created_at, updated_at)
      SELECT projects.id, 'Tasks', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM projects
      WHERE NOT EXISTS (
        SELECT 1 FROM task_lists WHERE task_lists.project_id = projects.id
      )
    SQL
    execute <<~SQL
      UPDATE tasks
      SET task_list_id = (
        SELECT task_lists.id
        FROM task_lists
        WHERE task_lists.project_id = tasks.project_id
        ORDER BY task_lists.position, task_lists.id
        LIMIT 1
      )
      WHERE task_list_id IS NULL
    SQL
    change_column_null :tasks, :task_list_id, false

    update_polymorphic_type(:agent_events, :subject_type, "Message", "ChatMessage")
    update_polymorphic_type(:agent_events, :subject_type, "TodoAssignment", "TaskAssignment")
    update_polymorphic_type(:agent_events, :subject_type, "TodoComment", "TaskComment")
    update_polymorphic_type(:reactions, :reactable_type, "Message", "ChatMessage")
    update_polymorphic_type(:reactions, :reactable_type, "Todo", "Task")
    update_polymorphic_type(:reactions, :reactable_type, "TodoComment", "TaskComment")
    update_polymorphic_type(:action_text_rich_texts, :record_type, "Todo", "Task")
    update_polymorphic_type(:action_text_rich_texts, :record_type, "TodoComment", "TaskComment")
    update_polymorphic_type(:active_storage_attachments, :record_type, "Message", "ChatMessage")

    execute "UPDATE agent_events SET event_type = 'chat_message_mentioned' WHERE event_type = 'mentioned'"
    execute "UPDATE agent_events SET event_type = 'task_comment_mentioned' WHERE event_type = 'comment_mentioned'"
    execute "UPDATE agent_events SET event_type = 'task_assigned' WHERE event_type = 'todo_assigned'"
    execute "UPDATE agent_events SET event_type = 'board_post_scheduled' WHERE event_type = 'board_scheduled'"
    execute "UPDATE search_documents SET source_type = 'chat_message' WHERE source_type = 'message'"
    execute "UPDATE search_documents SET source_type = 'task' WHERE source_type = 'todo'"
    execute "UPDATE search_documents SET source_type = 'task_comment' WHERE source_type = 'todo_comment'"
  end

  def down
    change_column_null :tasks, :task_list_id, true

    execute "UPDATE search_documents SET source_type = 'todo_comment' WHERE source_type = 'task_comment'"
    execute "UPDATE search_documents SET source_type = 'todo' WHERE source_type = 'task'"
    execute "UPDATE search_documents SET source_type = 'message' WHERE source_type = 'chat_message'"
    execute "UPDATE agent_events SET event_type = 'board_scheduled' WHERE event_type = 'board_post_scheduled'"
    execute "UPDATE agent_events SET event_type = 'todo_assigned' WHERE event_type = 'task_assigned'"
    execute "UPDATE agent_events SET event_type = 'comment_mentioned' WHERE event_type = 'task_comment_mentioned'"
    execute "UPDATE agent_events SET event_type = 'mentioned' WHERE event_type = 'chat_message_mentioned'"

    update_polymorphic_type(:active_storage_attachments, :record_type, "ChatMessage", "Message")
    update_polymorphic_type(:action_text_rich_texts, :record_type, "TaskComment", "TodoComment")
    update_polymorphic_type(:action_text_rich_texts, :record_type, "Task", "Todo")
    update_polymorphic_type(:reactions, :reactable_type, "TaskComment", "TodoComment")
    update_polymorphic_type(:reactions, :reactable_type, "Task", "Todo")
    update_polymorphic_type(:reactions, :reactable_type, "ChatMessage", "Message")
    update_polymorphic_type(:agent_events, :subject_type, "TaskComment", "TodoComment")
    update_polymorphic_type(:agent_events, :subject_type, "TaskAssignment", "TodoAssignment")
    update_polymorphic_type(:agent_events, :subject_type, "ChatMessage", "Message")

    rename_column :task_assignments, :assigned_by_id, :assigner_id
    rename_column :task_assignments, :task_id, :todo_id
    rename_column :task_comments, :task_id, :todo_id
    rename_column :tasks, :task_list_id, :todo_list_id

    rename_table :task_assignments, :todo_assignments
    rename_table :task_comments, :todo_comments
    rename_table :tasks, :todos
    rename_table :task_lists, :todo_lists
    rename_table :chat_messages, :messages
  end

  private

  def update_polymorphic_type(table, column, from, to)
    execute <<~SQL
      UPDATE #{quote_table_name(table)}
      SET #{quote_column_name(column)} = #{connection.quote(to)}
      WHERE #{quote_column_name(column)} = #{connection.quote(from)}
    SQL
  end
end
