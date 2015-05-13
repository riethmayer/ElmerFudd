module ElmerFudd
  class RedirectFailedFilter
    include Filter
    def initialize(producer, error_queue, exception: Exception,
                   exception_message_matches: /.*/)
      @producer = producer
      @error_queue = error_queue
      @exception = exception
      @exception_message_matches = exception_message_matches
    end

    def call(env, message, filters)
      call_next(env, message, filters)
    rescue @exception => e
      if e.message =~ @exception_message_matches
        @producer.cast @error_queue, message.payload
      else
        raise
      end
    end
  end
end
