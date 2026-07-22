class AgentApproval < ApplicationRecord
  class ResolutionError < StandardError; end

  STATES = %w[pending resolved expired cancelled].freeze
  MAX_JSON_BYTES = 64.kilobytes

  belongs_to :agent_event
  belongs_to :resolved_by, class_name: "User", optional: true
  scope :pending, -> { where(state: "pending") }

  validates :state, inclusion: { in: STATES }
  validates :agent_event_id, uniqueness: { conditions: -> { where(state: "pending") } }, if: :pending?
  validate :options_are_valid
  validate :permission_data_is_bounded
  after_create :mark_event_waiting!
  after_create_commit :broadcast_work_status
  after_update_commit :broadcast_work_status, if: :saved_change_to_state?

  def pending? = state == "pending"

  def resolve!(option_id, resolver:)
    raise ResolutionError, "Only a human can resolve an approval" unless resolver&.human?
    with_lock do
      if state == "resolved"
        return self if selected_option_id == option_id
        raise ResolutionError, "Approval was already resolved with another option"
      end
      raise ResolutionError, "Approval is no longer pending" unless pending?
      raise ResolutionError, "Option is not valid for this request" unless option_ids.include?(option_id)
      update!(state: "resolved", selected_option_id: option_id, resolved_by: resolver, resolved_at: Time.current)
      agent_event.transition_to!("running") if agent_event.reload.state == "waiting_for_approval"
    end
    AgentApprovals::Waiters.signal(id)
    self
  end

  def expire!
    with_lock do
      return unless pending?
      update!(state: "expired", expired_at: Time.current)
      agent_event.transition_to!("cancelled") if agent_event.reload.state.in?(%w[running waiting_for_approval queued])
    end
    AgentApprovals::Waiters.signal(id)
  end

  def cancel!
    with_lock do
      return unless pending?
      update!(state: "cancelled", cancelled_at: Time.current)
      agent_event.transition_to!("cancelled") if agent_event.reload.state.in?(%w[running waiting_for_approval queued])
    end
    AgentApprovals::Waiters.signal(id)
  end

  def option_ids = options.select { |option| option.key?("optionId") }.map { |option| option["optionId"] }

  private
    def broadcast_work_status
      agent_event.send(:broadcast_work_status)
    end

    def mark_event_waiting! = agent_event.transition_to!("waiting_for_approval")

    def options_are_valid
      ids = option_ids
      errors.add(:options, "must contain unique optionId values") if ids.empty? || ids.length != options.length || ids.uniq.length != ids.length
    end

    def permission_data_is_bounded
      errors.add(:base, "Permission request is too large") if JSON.generate([ request_id, options, details ]).bytesize > MAX_JSON_BYTES
    rescue JSON::GeneratorError
      errors.add(:base, "Permission request must be JSON compatible")
    end
end
