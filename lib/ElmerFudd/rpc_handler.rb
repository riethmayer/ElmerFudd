module ElmerFudd
  class RpcHandler < DirectHandler
    def call(env, message)
      reply(env, message, super)
    end

    def reply(env, original_message, response)
      exchange(env).publish(response.to_s, routing_key: original_message.properties.reply_to,
                            correlation_id: original_message.properties.correlation_id)
    end
  end
end
