module ElmerFudd
  class ActiveRecordConnectionPoolFilter
    extend Filter
    def self.call(env, message, filters)
      retry_num = 0
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          call_next(env, message, filters)
        end
      rescue ActiveRecord::ConnectionTimeoutError
        retry_num += 1
        if retry_num <= 5
          sleep 1
          retry
        else
          raise
        end
      end
    end
  end
end
