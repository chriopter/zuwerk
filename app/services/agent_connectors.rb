module AgentConnectors
  class << self
    attr_writer :registry
    def registry = (@registry ||= Registry.new)
  end
end
