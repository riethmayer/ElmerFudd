module ElmerFudd
  module Filter
    def call_next(env, message, filters)
      next_filter, *remainder = filters
      if remainder.empty?
        next_filter.call(env, message)
      else
        next_filter.call(env, message, remainder)
      end
    end
  end
end
