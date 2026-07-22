class DatabaseController < ApplicationController
  SENSITIVE_COLUMN = /(password|token|secret|digest|credential|external_session_id|\Akey\z)/i
  ROW_LIMIT = 100

  before_action :require_human!
  before_action :require_admin!
  before_action :set_workspace_navigation
  before_action :set_tables

  def index
  end

  def show
    @table = params[:table]
    raise ActiveRecord::RecordNotFound unless @tables.include?(@table)

    connection = ActiveRecord::Base.connection
    @columns = connection.columns(@table)
    @indexes = connection.indexes(@table)
    @foreign_keys = connection.foreign_keys(@table)
    @primary_key = connection.primary_key(@table)
    quoted_table = connection.quote_table_name(@table)
    order = @primary_key ? " ORDER BY #{connection.quote_column_name(@primary_key)} DESC" : ""
    records = connection.select_all("SELECT * FROM #{quoted_table}#{order} LIMIT #{ROW_LIMIT}").to_a
    @rows = records.map { |record| redact(record) }
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
  end

  def redact(record)
    record.to_h do |column, value|
      [ column, column.match?(SENSITIVE_COLUMN) && value.present? ? "[REDACTED]" : value ]
    end
  end
end
