class DispatchDueBoardAutomationsJob < ApplicationJob
  queue_as :default

  def perform
    BoardAutomation.due.find_each(&:dispatch_due!)
  end
end
