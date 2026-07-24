class DispatchDueBriefingsJob < ApplicationJob
  queue_as :default

  def perform
    Briefing.due.find_each(&:dispatch_due!)
  end
end
