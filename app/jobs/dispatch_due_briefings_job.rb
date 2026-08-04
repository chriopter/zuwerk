class DispatchDueBriefingsJob < ApplicationJob
  queue_as :default

  def perform
    Briefing.due.includes(:project).find_each do |briefing|
      Current.set(account: briefing.project.account) { briefing.dispatch_due! }
    end
  end
end
