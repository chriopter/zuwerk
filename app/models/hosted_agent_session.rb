class HostedAgentSession < ApplicationRecord
  belongs_to :hosted_agent
  belongs_to :origin, polymorphic: true

  before_validation -> { self.last_used_at ||= Time.current }, on: :create

  validates :external_session_id, presence: true
  validates :origin_id, uniqueness: { scope: [ :hosted_agent_id, :origin_type ] }

  def origin_label
    if origin.respond_to?(:name)
      origin.name
    elsif origin.respond_to?(:title)
      origin.title
    else
      "#{origin_type} ##{origin_id}"
    end
  end
end
