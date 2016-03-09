require 'ElmerFudd/version'
require 'bunny'
require 'thread'
require 'json'

module ElmerFudd
  DEFAULT_CONTENT_TYPE = Bunny::Channel::DEFAULT_CONTENT_TYPE

  require 'ElmerFudd/publisher'
  require 'ElmerFudd/json_publisher'

  require 'ElmerFudd/filter'
  require 'ElmerFudd/direct_handler'
  require 'ElmerFudd/topic_handler'
  require 'ElmerFudd/rpc_handler'
  if defined?(Rspec)
    require 'ElmerFudd/rspec'
  end
  require 'ElmerFudd/worker'


  require 'ElmerFudd/active_record_connection_pool_filter'
  require 'ElmerFudd/airbrake_filter'
  require 'ElmerFudd/exception_notification_filter'
  require 'ElmerFudd/discard_return_value_filter'
  require 'ElmerFudd/drop_failed_filter'
  require 'ElmerFudd/json_filter'
  require 'ElmerFudd/redirect_failed_filter'
  require 'ElmerFudd/retry_filter'
  require 'ElmerFudd/benchmark_filter'
end
