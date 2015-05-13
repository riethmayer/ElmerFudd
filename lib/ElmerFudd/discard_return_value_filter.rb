module ElmerFudd
  class DiscardReturnValueFilter
    extend Filter
    def self.call(env, message, filters)
      call_next(env, message, filters)
      nil
    end
  end
end
