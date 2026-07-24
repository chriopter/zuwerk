class Briefing < ApplicationRecord
  include ActivityTrackable

  FREQUENCIES = {
    "hourly" => 1.hour,
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month
  }.freeze

  belongs_to :project
  belongs_to :creator, class_name: "User"
  belongs_to :agent, class_name: "User"
  has_many :comments, class_name: "BriefingComment", dependent: :destroy
  has_rich_text :prompt

  before_validation :set_initial_next_run_at, on: :create
  before_validation :set_initial_activity, on: :create
  before_validation :reschedule_for_changed_frequency, on: :update

  validates :title, presence: true, length: { maximum: 160 }
  validates :prompt, presence: true
  validates :frequency, inclusion: { in: FREQUENCIES.keys }
  validate :agent_identity
  validate :prompt_length

  scope :due, -> { where(active: true, next_run_at: ..Time.current) }
  after_create_commit :register_creator_participation

  def dispatch_due!
    with_lock do
      return unless active? && next_run_at <= Time.current

      scheduled_for = next_run_at
      comment = create_occurrence!(scheduled_for)
      self.next_run_at = next_occurrence_from([ scheduled_for, Time.current ].max)
      save!
      comment
    end
  rescue ActiveRecord::RecordNotUnique
    with_lock do
      occurrence = comments.find_by!(scheduled_for: next_run_at)
      self.next_run_at = next_occurrence_from([ next_run_at, Time.current ].max)
      save!
      occurrence
    end
  end

  def run_now!
    with_lock { create_occurrence!(Time.current) }
  end

  def pause!
    update!(active: false)
  end

  def resume!
    with_lock { update!(active: true, next_run_at: next_occurrence_from(Time.current)) }
  end

  def frequency_label
    {
      "hourly" => "Every hour",
      "daily" => "Every day",
      "weekly" => "Every week",
      "monthly" => "Every month"
    }.fetch(frequency)
  end

  private

  def create_occurrence!(scheduled_for)
    transaction do
      comment = comments.create!(
        author: agent,
        title: title,
        scheduled_for: scheduled_for,
        prompt_snapshot: prompt.to_plain_text
      )
      event = comment.agent_events.create!(recipient: agent, event_type: "briefing_scheduled")
      comment.update!(agent_event: event)
      comment
    end
  end

  def set_initial_next_run_at
    self.next_run_at ||= next_occurrence_from(Time.current) if FREQUENCIES.key?(frequency)
  end

  def set_initial_activity
    self.last_activity_at ||= Time.current
  end

  def register_creator_participation
    register_participant!(creator)
  end

  def reschedule_for_changed_frequency
    self.next_run_at = next_occurrence_from(Time.current) if will_save_change_to_frequency? && FREQUENCIES.key?(frequency)
  end

  def next_occurrence_from(time)
    time + FREQUENCIES.fetch(frequency)
  end

  def agent_identity
    errors.add(:agent, "must be an agent") unless agent&.agent?
  end

  def prompt_length
    errors.add(:prompt, "is too long (maximum is 20000 characters)") if prompt.to_plain_text.length > 20_000
  end
end
