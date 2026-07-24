class ReplaceBoardWithBriefings < ActiveRecord::Migration[8.1]
  def up
    rename_table :board_automations, :briefings
    rename_column :briefings, :cadence, :frequency

    rename_table :board_posts, :briefing_comments
    rename_column :briefing_comments, :board_automation_id, :briefing_id

    add_column :briefings, :activity_at, :datetime
    execute <<~SQL
      UPDATE briefings
      SET activity_at = COALESCE(
        (
          SELECT MAX(briefing_comments.published_at)
          FROM briefing_comments
          WHERE briefing_comments.briefing_id = briefings.id
        ),
        briefings.created_at
      )
    SQL
    change_column_null :briefings, :activity_at, false
    add_index :briefings, [ :project_id, :activity_at ]

    change_column_null :briefing_comments, :title, true
    change_column_null :briefing_comments, :scheduled_for, true
    change_column_null :briefing_comments, :prompt_snapshot, true

    execute "UPDATE action_text_rich_texts SET record_type = 'Briefing' WHERE record_type = 'BoardAutomation'"
    execute "UPDATE action_text_rich_texts SET record_type = 'BriefingComment' WHERE record_type = 'BoardPost'"
    execute "UPDATE active_storage_attachments SET record_type = 'Briefing' WHERE record_type = 'BoardAutomation'"
    execute "UPDATE active_storage_attachments SET record_type = 'BriefingComment' WHERE record_type = 'BoardPost'"
    execute "UPDATE agent_events SET subject_type = 'BriefingComment', event_type = 'briefing_scheduled' WHERE subject_type = 'BoardPost'"
    execute "UPDATE search_documents SET source_type = 'briefing_comment' WHERE source_type = 'board_post'"
  end

  def down
    execute "UPDATE search_documents SET source_type = 'board_post' WHERE source_type = 'briefing_comment'"
    execute "UPDATE agent_events SET subject_type = 'BoardPost', event_type = 'board_post_scheduled' WHERE subject_type = 'BriefingComment'"
    execute "UPDATE active_storage_attachments SET record_type = 'BoardPost' WHERE record_type = 'BriefingComment'"
    execute "UPDATE active_storage_attachments SET record_type = 'BoardAutomation' WHERE record_type = 'Briefing'"
    execute "UPDATE action_text_rich_texts SET record_type = 'BoardPost' WHERE record_type = 'BriefingComment'"
    execute "UPDATE action_text_rich_texts SET record_type = 'BoardAutomation' WHERE record_type = 'Briefing'"

    execute "UPDATE briefing_comments SET prompt_snapshot = '' WHERE prompt_snapshot IS NULL"
    execute "UPDATE briefing_comments SET scheduled_for = created_at WHERE scheduled_for IS NULL"
    execute "UPDATE briefing_comments SET title = 'Comment' WHERE title IS NULL"
    change_column_null :briefing_comments, :prompt_snapshot, false
    change_column_null :briefing_comments, :scheduled_for, false
    change_column_null :briefing_comments, :title, false
    remove_index :briefings, [ :project_id, :activity_at ]
    remove_column :briefings, :activity_at

    rename_column :briefing_comments, :briefing_id, :board_automation_id
    rename_table :briefing_comments, :board_posts
    rename_column :briefings, :frequency, :cadence
    rename_table :briefings, :board_automations
  end
end
