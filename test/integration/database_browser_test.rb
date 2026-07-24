require "test_helper"

class DatabaseBrowserTest < ActionDispatch::IntegrationTest
  setup do
    @human = User.create!(name: "DB Admin", email: "db-admin@example.com", password: "password1", admin: true)
    @agent = User.create!(name: "DB Agent", kind: :agent, api_token: "sensitive-agent-token")
    post session_path, params: { email: @human.email, password: "password1" }
  end

  test "administrators browse grouped tables beside the selected table data" do
    get database_path
    assert_redirected_to database_table_path("users")
    follow_redirect!

    assert_response :success
    assert_select ".workspace-topbar a[aria-current='page'][href='#{database_path}']", text: "Database"
    assert_select "h1", text: "users"
    assert_select "[data-table-navigation]" do
      assert_select "section > h2" do |headings|
        assert_equal [ "Users", "User data", "Agents", "Active Storage / Action Text", "Rails internal" ], headings.map(&:text)
      end
    end
    assert_select "[data-table-group='users'] a[href='#{database_table_path("users")}']"
    assert_select "[data-table-group='user-data'] a[href='#{database_table_path("messages")}']"
    assert_select "[data-table-group='agents'] a[href='#{database_table_path("agent_events")}']"
    assert_select "[data-table-group='active-storage-action-text'] a[href='#{database_table_path("active_storage_blobs")}']"
    assert_select "[data-table-group='rails-internal'] a[href='#{database_table_path("schema_migrations")}']"
    assert_select "[data-database-section='data']"
  end

  test "table page shows structure indexes and redacted data" do
    get database_table_path("users")

    assert_response :success
    assert_select "h1", text: "users"
    assert_select "[data-database-section='structure']", text: /api_token_digest/
    assert_select "[data-database-section='indexes']", minimum: 1
    assert_select "[data-database-section='data']", text: /DB Agent/
    assert_select "[data-database-section='data']", text: /\[REDACTED\]/
    assert_select "[data-database-section='data']", text: /sensitive-agent-token/, count: 0
    assert_select "a[href='#{database_record_path("users", @agent.id)}']", text: "View"
  end

  test "record details preserve navigation and redact sensitive values" do
    get database_record_path("users", @agent.id)

    assert_response :success
    assert_select "h1", text: "users / #{@agent.id}"
    assert_select "a[href='#{database_table_path("users")}']", text: "Back to users"
    assert_select "[data-table-group='users'] a[aria-current='page'][href='#{database_table_path("users")}']"
    assert_select "[data-database-record]", text: /DB Agent/
    assert_select "[data-database-record]", text: /\[REDACTED\]/
    assert_select "[data-database-record]", text: /sensitive-agent-token/, count: 0
  end

  test "empty tables show an explicit empty state" do
    AgentInvitation.delete_all

    get database_table_path("agent_invitations")

    assert_response :success
    assert_select "[data-database-empty]", text: "No rows"
    assert_select "[data-database-section='data'] tbody tr", count: 0
  end

  test "unknown tables are rejected and signed-out visitors cannot browse" do
    get database_table_path("users; DROP TABLE users")
    assert_response :not_found

    delete session_path
    get database_path
    assert_redirected_to new_session_path

    get database_record_path("users", @agent.id)
    assert_redirected_to new_session_path
  end

  test "invalid record parameters and records from other tables are rejected" do
    get database_record_path("missing_table", @agent.id)
    assert_response :not_found

    get database_record_path("users", "not-a-record-id")
    assert_response :not_found

    get database_record_path("users", "1 OR 1=1")
    assert_response :not_found

    get database_record_path("users", -1)
    assert_response :not_found
  end

  test "non-admin humans cannot access the database browser or see its navigation" do
    delete session_path
    human = User.create!(name: "DB Reader", email: "db-reader@example.com", password: "password1")
    post session_path, params: { email: human.email, password: "password1" }

    get database_path
    assert_redirected_to root_path

    get database_record_path("users", @agent.id)
    assert_redirected_to root_path

    follow_redirect!
    assert_select ".workspace-topbar a[href='#{database_path}']", count: 0
  end
end
