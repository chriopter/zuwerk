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

ActiveRecord::Schema[8.1].define(version: 2026_07_21_000000) do
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

  create_table "messages", force: :cascade do |t|
    t.integer "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_messages_on_author_id"
  end

  create_table "reactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emoji", null: false
    t.integer "message_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["message_id"], name: "index_reactions_on_message_id"
    t.index ["user_id", "message_id", "emoji"], name: "index_reactions_on_user_id_and_message_id_and_emoji", unique: true
    t.index ["user_id"], name: "index_reactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "api_token_digest"
    t.datetime "created_at", null: false
    t.string "email"
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.index ["api_token_digest"], name: "index_users_on_api_token_digest", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "agent_invitations", "users", column: "inviter_id"
  add_foreign_key "messages", "users", column: "author_id"
  add_foreign_key "reactions", "messages"
  add_foreign_key "reactions", "users"
end
