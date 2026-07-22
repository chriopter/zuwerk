# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_22_211000) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_approvals", force: :cascade do |t|
    t.integer "agent_event_id", null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.json "details", default: {}, null: false
    t.datetime "expired_at"
    t.json "options", default: [], null: false
    t.json "request_id", null: false
    t.datetime "resolved_at"
    t.integer "resolved_by_id"
    t.json "selected_option_id"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_event_id"], name: "index_agent_approvals_on_agent_event_id"
    t.index ["agent_event_id"], name: "index_agent_approvals_one_pending_per_event", unique: true, where: "state = 'pending'"
    t.index ["resolved_by_id"], name: "index_agent_approvals_on_resolved_by_id"
  end

  create_table "agent_events", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "event_type", null: false
    t.datetime "finished_at"
    t.string "last_error"
    t.string "public_id", null: false
    t.integer "recipient_id", null: false
    t.datetime "runtime_recovered_at"
    t.datetime "started_at"
    t.string "state", default: "queued", null: false
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.datetime "waiting_at"
    t.integer "watchdog_attempts", default: 0, null: false
    t.datetime "watchdog_retry_at"
    t.index ["delivered_at", "watchdog_retry_at"], name: "index_agent_events_for_watchdog"
    t.index ["event_type", "recipient_id", "subject_type", "subject_id"], name: "index_agent_events_on_unique_delivery", unique: true
    t.index ["public_id"], name: "index_agent_events_on_public_id", unique: true
    t.index ["recipient_id", "accepted_at"], name: "index_agent_events_on_recipient_id_and_accepted_at"
    t.index ["recipient_id", "state", "created_at"], name: "index_agent_events_on_recipient_state_created"
    t.index ["recipient_id"], name: "index_agent_events_on_recipient_id"
    t.index ["subject_type", "subject_id"], name: "index_agent_events_on_subject"
  end

  create_table "agent_invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.integer "inviter_id", null: false
    t.datetime "redeemed_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["inviter_id"], name: "index_agent_invitations_on_inviter_id"
    t.index ["token_digest"], name: "index_agent_invitations_on_token_digest", unique: true
  end

  create_table "agent_subscriptions", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.datetime "created_at", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_agent_subscriptions_on_agent_id"
    t.index ["project_id", "agent_id"], name: "index_agent_subscriptions_on_project_id_and_agent_id", unique: true
    t.index ["project_id"], name: "index_agent_subscriptions_on_project_id"
  end

  create_table "hosted_agent_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_session_id", null: false
    t.integer "hosted_agent_id", null: false
    t.datetime "last_used_at", null: false
    t.integer "origin_id", null: false
    t.string "origin_type", null: false
    t.datetime "updated_at", null: false
    t.index ["hosted_agent_id", "origin_type", "origin_id"], name: "index_hosted_agent_sessions_on_agent_and_origin", unique: true
    t.index ["hosted_agent_id"], name: "index_hosted_agent_sessions_on_hosted_agent_id"
    t.index ["origin_type", "origin_id"], name: "index_hosted_agent_sessions_on_origin_type_and_origin_id"
  end

  create_table "hosted_agents", force: :cascade do |t|
    t.datetime "bridge_connected_at"
    t.text "bridge_last_error"
    t.string "container_id"
    t.datetime "created_at", null: false
    t.text "last_error"
    t.datetime "last_started_at"
    t.datetime "last_stopped_at"
    t.string "runtime", null: false
    t.string "state", default: "stopped", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_hosted_agents_on_user_id", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.integer "agent_event_id"
    t.integer "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_event_id"], name: "index_messages_on_agent_event_id", unique: true
    t.index ["author_id"], name: "index_messages_on_author_id"
    t.index ["project_id"], name: "index_messages_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower(name)", name: "index_projects_on_lower_name", unique: true
  end

  create_table "reactions", force: :cascade do |t|
    t.integer "author_id", null: false
    t.datetime "created_at", null: false
    t.string "emoji", null: false
    t.integer "reactable_id", null: false
    t.string "reactable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id", "reactable_type", "reactable_id", "emoji"], name: "index_reactions_on_author_reactable_emoji", unique: true
    t.index ["author_id"], name: "index_reactions_on_author_id"
    t.index ["reactable_type", "reactable_id"], name: "index_reactions_on_reactable_type_and_reactable_id"
  end

  create_table "room_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "notify_agents", default: false, null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_room_settings_on_project_id", unique: true
  end

  create_table "todo_assignments", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.integer "assigner_id", null: false
    t.datetime "created_at", null: false
    t.integer "todo_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_todo_assignments_on_agent_id"
    t.index ["assigner_id"], name: "index_todo_assignments_on_assigner_id"
    t.index ["todo_id", "agent_id"], name: "index_todo_assignments_on_todo_id_and_agent_id", unique: true
    t.index ["todo_id"], name: "index_todo_assignments_on_todo_id"
  end

  create_table "todo_comments", force: :cascade do |t|
    t.integer "agent_event_id"
    t.integer "author_id", null: false
    t.datetime "created_at", null: false
    t.integer "todo_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_event_id"], name: "index_todo_comments_on_agent_event_id", unique: true
    t.index ["author_id"], name: "index_todo_comments_on_author_id"
    t.index ["todo_id"], name: "index_todo_comments_on_todo_id"
  end

  create_table "todos", force: :cascade do |t|
    t.string "ancestry"
    t.datetime "created_at", null: false
    t.integer "creator_id", null: false
    t.integer "position", default: 0, null: false
    t.integer "project_id", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["ancestry"], name: "index_todos_on_ancestry"
    t.index ["creator_id"], name: "index_todos_on_creator_id"
    t.index ["project_id", "ancestry", "position"], name: "index_todos_on_project_id_and_ancestry_and_position"
    t.index ["project_id"], name: "index_todos_on_project_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "api_token_digest"
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "heartbeat_at"
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.string "working_label"
    t.boolean "working_status", default: false, null: false
    t.index ["api_token_digest"], name: "index_users_on_api_token_digest", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_approvals", "agent_events"
  add_foreign_key "agent_approvals", "users", column: "resolved_by_id"
  add_foreign_key "agent_events", "users", column: "recipient_id"
  add_foreign_key "agent_invitations", "users", column: "inviter_id"
  add_foreign_key "agent_subscriptions", "projects"
  add_foreign_key "agent_subscriptions", "users", column: "agent_id"
  add_foreign_key "hosted_agent_sessions", "hosted_agents"
  add_foreign_key "hosted_agents", "users"
  add_foreign_key "messages", "agent_events"
  add_foreign_key "messages", "projects"
  add_foreign_key "messages", "users", column: "author_id"
  add_foreign_key "reactions", "users", column: "author_id"
  add_foreign_key "room_settings", "projects"
  add_foreign_key "todo_assignments", "todos"
  add_foreign_key "todo_assignments", "users", column: "agent_id"
  add_foreign_key "todo_assignments", "users", column: "assigner_id"
  add_foreign_key "todo_comments", "agent_events"
  add_foreign_key "todo_comments", "todos"
  add_foreign_key "todo_comments", "users", column: "author_id"
  add_foreign_key "todos", "projects"
  add_foreign_key "todos", "users", column: "creator_id"
end
