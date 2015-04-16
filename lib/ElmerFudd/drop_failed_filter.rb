module ElmerFudd
  class DropFailedFilter
    include Filter

    def self.call(env, message, filters)
      new.call(env, message, filters)
    end

    def initialize(exception: Exception,
                   exception_message_matches: /.*/)
      @exception = exception
      @exception_message_matches = exception_message_matches
    end

    def call(env, message, filters)
      call_next(env, message, filters)
    rescue @exception => e
      if e.message =~ @exception_message_matches
        env.logger.info "Ignoring failed payload: #{message.payload}"
        env.logger.debug "#{e.class}: #{e.message}"
        e.backtrace.each { |l| env.logger.debug(l) }
      else
        raise
      end
    end
  end
end
