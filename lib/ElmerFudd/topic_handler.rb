module ElmerFudd
  class TopicHandler < DirectHandler
    def exchange(env)
      env.channel.topic(@route.exchange_name, durable: false, internal: false, autodelete: false)
    end
  end
end
