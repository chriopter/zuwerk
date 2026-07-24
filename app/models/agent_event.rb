class AgentEvent < ApplicationRecord
  class InvalidTransition < StandardError; end

  STATES = %w[queued running waiting_for_approval completed failed cancelled].freeze
  TERMINAL_STATES = %w[completed failed cancelled].freeze
  TRANSITIONS = {
    "queued" => %w[running cancelled],
    "running" => %w[waiting_for_approval completed failed cancelled],
    "waiting_for_approval" => %w[running failed cancelled]
  }.freeze
  belongs_to :recipient, class_name: "User"
  belongs_to :subject, polymorphic: true
  has_one :publication_chat_message, class_name: "ChatMessage", dependent: :nullify
  has_one :publication_task_comment, class_name: "TaskComment", dependent: :nullify
  has_one :publication_briefing_comment, class_name: "BriefingComment", dependent: :nullify
  has_many :agent_approvals, dependent: :destroy

  before_validation :assign_public_id, on: :create
  after_create_commit -> { DeliverAgentEventJob.perform_later(self) }
  after_create_commit :broadcast_work_status
  after_update_commit :broadcast_work_status, if: :saved_change_to_state?

  attr_readonly :public_id

  validates :public_id, presence: true, uniqueness: true
  validates :event_type, inclusion: { in: %w[chat_message_mentioned task_comment_mentioned task_assigned briefing_comment_mentioned briefing_scheduled] }
  validates :state, inclusion: { in: STATES }
  validates :recipient_id, uniqueness: { scope: [ :event_type, :subject_type, :subject_id ] }

  scope :accepted, -> { where.not(accepted_at: nil) }

  def self.claim_next_for!(recipient)
    transaction do
      recipient.lock!
      return if where(recipient: recipient, state: %w[running waiting_for_approval]).exists?

      event = where(recipient: recipient, state: "queued").order(:created_at, :id).first
      event&.transition_to!("running")
      event
    end
  end

  # The recipient row is the routing mutex shared by connector registration and
  # every kind of event claim.
  def self.claim_for_fallback!(event)
    transaction do
      recipient = User.lock.find(event.recipient_id)
      event.reload
      return unless event.state.in?(%w[queued running])
      return if recipient.external_connector_present?

      active = where(recipient: recipient, state: %w[running waiting_for_approval]).order(:created_at, :id).first
      return event if event.state == "running" && active == event && event.connector_connection_id.nil?
      return if active

      next_event = where(recipient: recipient, state: "queued").order(:created_at, :id).first
      next_event&.transition_to!("running")
      next_event
    end
  end

  def self.claim_for_connector!(recipient_id, connection_id)
    transaction do
      recipient = User.lock.find(recipient_id)
      return unless recipient.connector_connection_id == connection_id && recipient.external_connector_present?

      recipient.update_columns(connector_heartbeat_at: Time.current, updated_at: Time.current)
      active = where(recipient: recipient, state: %w[running waiting_for_approval]).order(:created_at, :id).first
      if active&.state == "running"
        return if active.connector_connection_id.nil?
        active.update_columns(connector_connection_id: connection_id, updated_at: Time.current)
        return active
      end
      return if active

      event = where(recipient: recipient, state: "queued").order(:created_at, :id).first
      event&.transition_to!("running")
      event&.update_columns(connector_connection_id: connection_id, updated_at: Time.current)
      event
    end
  end

  def self.schedule_next_for!(recipient)
    event = where(recipient: recipient, state: "queued").order(:created_at, :id).first
    DeliverAgentEventJob.perform_later(event) if event
  end

  def transition_to!(new_state)
    new_state = new_state.to_s
    with_lock do
      raise InvalidTransition, "Cannot transition AgentEvent from #{state} to #{new_state}" unless TRANSITIONS.fetch(state, []).include?(new_state)

      attributes = { state: new_state }
      attributes[:started_at] = Time.current if new_state == "running" && started_at.nil?
      attributes[:waiting_at] = Time.current if new_state == "waiting_for_approval"
      attributes[:finished_at] = Time.current if TERMINAL_STATES.include?(new_state)
      update!(attributes)
    end
  end

  def terminalize_failure!(error, expected_connector_owner: nil)
    changed = false
    with_lock do
      return if state.in?(TERMINAL_STATES)
      return if expected_connector_owner && connector_connection_id != expected_connector_owner
      update!(state: "failed", finished_at: Time.current, last_error: error.message.to_s.truncate(255))
      changed = true
    end
    return unless changed
    agent_approvals.pending.find_each(&:expire!)
    self.class.schedule_next_for!(recipient)
  end

  def active?
    accepted_at? && !delivered_at? && last_error.blank?
  end

  def failed?
    accepted_at? && !delivered_at? && last_error.present?
  end

  def task
    subject.task if event_type.in?(%w[task_assigned task_comment_mentioned])
  end

  def project
    task&.project || subject.project
  end

  def self.latest_for_chat(project)
    where(subject_type: "ChatMessage", subject_id: project.chat.messages.select(:id)).order(created_at: :desc, id: :desc).first
  end

  def self.latest_for_task(task)
    assignment_events = where(subject_type: "TaskAssignment", subject_id: task.assignments.select(:id))
    comment_events = where(subject_type: "TaskComment", subject_id: task.comments.select(:id))
    assignment_events.or(comment_events).order(created_at: :desc, id: :desc).first
  end

  def acknowledge!
    with_lock do
      unless accepted_at?
        update!(accepted_at: Time.current, last_error: nil)
        acknowledgement_target&.reactions&.find_or_create_by!(author: recipient, emoji: "👍")
      end
      self
    end
  end

  def payload
    {
      id: public_id,
      type: event_type,
      occurred_at: created_at.iso8601,
      recipient: { id: recipient.id, handle: recipient.handle },
      subject: { type: subject_type.underscore, id: subject_id },
      context: event_context
    }
  end

  private
    def broadcast_work_status
      broadcast_replace_to project.agent_turn_stream, target: "chat_agent_turn_status", partial: "agent_events/chat_status", locals: { project: project }
      return unless task

      broadcast_replace_to "task_#{task.id}_status", target: "task_#{task.id}_agent_status", partial: "agent_events/task_status", locals: { task: task }
      broadcast_replace_to project.agent_turn_stream, target: "task_#{task.id}_kanban_agent_status", partial: "agent_events/kanban_status", locals: { task: task }
    end

    def acknowledgement_target
      return task if event_type == "task_assigned"
      subject if event_type.in?(%w[briefing_comment_mentioned briefing_scheduled chat_message_mentioned task_comment_mentioned])
    end

    def event_context
      context = { project: { id: project.id, name: project.name } }
      if event_type.in?(%w[task_assigned task_comment_mentioned])
        context.merge(task: { id: task.id, title: task.title }, origin: "task")
      elsif event_type.in?(%w[briefing_comment_mentioned briefing_scheduled])
        briefing = subject.briefing
        comment = { id: subject.id }
        comment[:scheduled_for] = subject.scheduled_for.iso8601 if subject.scheduled_for
        context.merge(briefing: { id: briefing.id, title: briefing.title }, briefing_comment: comment, origin: "briefing")
      else
        context.merge(conversation: "chat")
      end
    end

    def assign_public_id
      self.public_id ||= SecureRandom.uuid
    end
end
