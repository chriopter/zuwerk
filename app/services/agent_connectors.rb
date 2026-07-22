module AgentConnectors
  class << self
    def registry = (@registry ||= Registry.new)
  end
end
