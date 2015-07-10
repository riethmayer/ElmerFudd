module ElmerFudd
  class ExceptionNotificationFilter
    extend Filter
    def self.call(env, message, filters)
      call_next(env, message, filters)
    rescue Exception => e
      ExceptionNotifier.notify_exception(e, env: Rails.env, data: {
                        payload: message.payload,
                        queue: message.route.queue_name,
                        exchange_name: message.route.exchange_name,
                        routing_key: message.delivery_info.routing_key,
                        matched_routing_key: message.route.routing_keys
                      })
      raise
    end
  end
end
