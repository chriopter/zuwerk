class BoardAutomation < ApplicationRecord
  CADENCES = {
    "hourly" => 1.hour,
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month
  }.freeze

  belongs_to :project
  belongs_to :creator, class_name: "User"
  belongs_to :agent, class_name: "User"
  has_many :board_posts, dependent: :destroy
  has_rich_text :prompt

  before_validation :set_initial_next_run_at, on: :create
  before_validation :reschedule_for_changed_cadence, on: :update

  validates :title, presence: true, length: { maximum: 160 }
  validates :prompt, presence: true
  validates :cadence, inclusion: { in: CADENCES.keys }
  validate :agent_identity
  validate :prompt_length

  scope :due, -> { where(active: true, next_run_at: ..Time.current) }

  def dispatch_due!
    with_lock do
      return unless active? && next_run_at <= Time.current

      scheduled_for = next_run_at
      post = create_occurrence!(scheduled_for)
      self.next_run_at = next_occurrence_from([ scheduled_for, Time.current ].max)
      save!
      post
    end
  rescue ActiveRecord::RecordNotUnique
    with_lock do
      occurrence = board_posts.find_by!(scheduled_for: next_run_at)
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

  def cadence_label
    { "hourly" => "Every hour", "daily" => "Every day", "weekly" => "Every week", "monthly" => "Every month" }.fetch(cadence)
  end

  private

  def create_occurrence!(scheduled_for)
    transaction do
      post = board_posts.create!(author: agent, title: title, scheduled_for: scheduled_for, prompt_snapshot: prompt.to_plain_text)
      event = post.agent_events.create!(recipient: agent, event_type: "board_scheduled")
      post.update!(agent_event: event)
      post
    end
  end

  def set_initial_next_run_at
    self.next_run_at ||= next_occurrence_from(Time.current) if CADENCES.key?(cadence)
  end

  def reschedule_for_changed_cadence
    self.next_run_at = next_occurrence_from(Time.current) if will_save_change_to_cadence? && CADENCES.key?(cadence)
  end

  def next_occurrence_from(time)
    time + CADENCES.fetch(cadence)
  end

  def agent_identity
    errors.add(:agent, "must be an agent") unless agent&.agent?
  end

  def prompt_length
    errors.add(:prompt, "is too long (maximum is 20000 characters)") if prompt.to_plain_text.length > 20_000
  end
end
