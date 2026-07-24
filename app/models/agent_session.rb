class AgentSession < ApplicationRecord
  CONTEXT_TYPES = %w[Briefing Chat Task].freeze

  belongs_to :agent, class_name: "User"
  belongs_to :project
  belongs_to :context, polymorphic: true

  validates :context_type, inclusion: { in: CONTEXT_TYPES }
  validates :external_session_id, presence: true
  validates :prompt_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :agent_identity
  validate :context_belongs_to_project

  scope :recent_first, -> { order(last_used_at: :desc, id: :desc) }

  def self.record_usage!(agent:, context:, external_session_id:)
    project = context.project
    session = find_or_initialize_by(agent: agent, context: context)
    now = Time.current
    if session.new_record?
      session.update!(
        project: project,
        external_session_id: external_session_id,
        prompt_count: 1,
        started_at: now,
        last_used_at: now
      )
      return session
    end

    session.with_lock do
      if session.external_session_id != external_session_id
        session.external_session_id = external_session_id
        session.started_at = now
        session.prompt_count = 0
      end
      session.project = project
      session.last_used_at = now
      session.prompt_count += 1
      session.save!
    end
    session
  end

  private

  def agent_identity
    errors.add(:agent, "must be an agent") unless agent&.agent?
  end

  def context_belongs_to_project
    errors.add(:context, "must belong to the project") if context&.project_id != project_id
  end
end
