module AgentApprovals
  module Waiters
    @mutex = Mutex.new
    @conditions = {}
    class << self
      def wait(id, timeout: 300)
        @mutex.synchronize do
          condition = (@conditions[id] ||= ConditionVariable.new)
          condition.wait(@mutex, timeout)
        ensure
          @conditions.delete(id)
        end
      end

      def signal(id) = @mutex.synchronize { @conditions[id]&.broadcast }
    end
  end
end
