module ElmerFudd
  class RpcHandler < DirectHandler
    def call(env, message)
      env.logger.debug "ElmerFudd RpcHandler.call queue_name: #{@route.queue_name}, exchange_name: #{@route.exchange_name}, filters: #{@filters.map(&:name)}, message: #{message.payload}"

      reply(env, message, super)
    end

    def reply(env, original_message, response)
      exchange(env).publish(response.to_s, routing_key: original_message.properties.reply_to,
                            correlation_id: original_message.properties.correlation_id)
    end
  end
end
