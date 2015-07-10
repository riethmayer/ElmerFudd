module ElmerFudd
  class RetryFilter
    include Filter

    def initialize(times, exception: Exception,
                   exception_message_matches: /.*/)
      @times = times
      @exception = exception
      @exception_message_matches = exception_message_matches
    end

    def call(env, message, filters)
      retry_num = 0
      begin
        call_next(env, message, filters)
      rescue @exception => e
        if e.message =~ @exception_message_matches && retry_num < @times
          retry_num += 1
          sleep Math.log(retry_num, 2)
          retry
        else
          raise
        end
      end
    end
  end
end
