module ElmerFudd
  class TopicHandler < DirectHandler
    def exchange(env)
      env.logger.debug "ElmerFudd TopicHandler.exchange queue_name: #{@route.queue_name}, exchange_name: #{@route.exchange_name}, filters: #{filters_names}"
      env.channel.topic(@route.exchange_name, durable: false, internal: false, autodelete: false)
    end
  end
end
