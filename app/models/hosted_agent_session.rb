class HostedAgentSession < ApplicationRecord
  belongs_to :hosted_agent
  belongs_to :project

  validates :external_session_id, presence: true
  validates :project_id, uniqueness: { scope: :hosted_agent_id }
end
