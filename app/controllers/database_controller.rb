class DatabaseController < ApplicationController
  SENSITIVE_COLUMN = /(password|token|secret|digest|credential|external_session_id|\Akey\z)/i
  ROW_LIMIT = 100
  TABLE_GROUPS = [
    [ "users", "Users" ],
    [ "user-data", "User data" ],
    [ "agents", "Agents" ],
    [ "active-storage-action-text", "Active Storage / Action Text" ],
    [ "rails-internal", "Rails internal" ]
  ].freeze
  AGENT_TABLES = %w[agent_events agent_invitations hosted_agent_sessions hosted_agents].freeze

  before_action :require_human!
  before_action :require_admin!
  before_action :set_workspace_navigation
  before_action :set_tables

  def index
    redirect_to database_table_path(@tables.include?("users") ? "users" : @tables.first)
  end

  def show
    set_table
    order = @primary_key ? " ORDER BY #{@connection.quote_column_name(@primary_key)} DESC" : ""
    records = @connection.select_all("SELECT * FROM #{@quoted_table}#{order} LIMIT #{ROW_LIMIT}").to_a
    @row_ids = records.map { |record| record[@primary_key] }
    @rows = records.map { |record| redact(record) }
  end

  def record
    set_table
    raise ActiveRecord::RecordNotFound unless @primary_key

    quoted_primary_key = @connection.quote_column_name(@primary_key)
    record = @connection.select_one(
      "SELECT * FROM #{@quoted_table} WHERE #{quoted_primary_key} = #{@connection.quote(params[:id])} LIMIT 1"
    )
    raise ActiveRecord::RecordNotFound unless record

    @record_id = record[@primary_key]
    @record = redact(record)
  end

  private

  def require_admin!
    redirect_to root_path, alert: "Administrator access required." unless current_user.admin?
  end

  def set_workspace_navigation
    @project = Project.default
    @projects = Project.order(:name)
    @sidebar_agents = User.agent.includes(:hosted_agent).order(:name)
  end

  def set_tables
    @tables = ActiveRecord::Base.connection.data_sources.sort
    @table_groups = TABLE_GROUPS.filter_map do |slug, label|
      tables = @tables.select { |table| table_group(table) == slug }
      [ slug, label, tables ] if tables.any?
    end
  end

  def set_table
    @table = params[:table]
    raise ActiveRecord::RecordNotFound unless @tables.include?(@table)

    @connection = ActiveRecord::Base.connection
    @columns = @connection.columns(@table)
    @indexes = @connection.indexes(@table)
    @foreign_keys = @connection.foreign_keys(@table)
    @primary_key = @connection.primary_key(@table)
    @quoted_table = @connection.quote_table_name(@table)
  end

  def table_group(table)
    case table
    when "ar_internal_metadata", "schema_migrations" then "rails-internal"
    when /\A(?:active_storage|action_text)_/ then "active-storage-action-text"
    when "users" then "users"
    when *AGENT_TABLES then "agents"
    else "user-data"
    end
  end

  def redact(record)
    record.to_h do |column, value|
      [ column, column.match?(SENSITIVE_COLUMN) && value.present? ? "[REDACTED]" : value ]
    end
  end
end
