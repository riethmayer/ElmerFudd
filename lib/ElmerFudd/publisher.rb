module ElmerFudd
  class Publisher
    def initialize(connection, uuid_service: -> { rand.to_s })
      @connection = connection
      @uuid_service = uuid_service
      @topic_x = {}
    end

    def notify(topic_exchange, routing_key, payload)
      @topic_x[topic_exchange] ||= channel.topic(topic_exchange)
      @topic_x[topic_exchange].publish payload.to_s, routing_key: routing_key
      nil
    end

    def cast(queue_name, payload)
      x.publish(payload.to_s, routing_key: queue_name)
      nil
    end

    def call(queue_name, payload, timeout: 10)
      mutex = Mutex.new
      resource = ConditionVariable.new
      correlation_id = @uuid_service.call
      consumer_tag = @uuid_service.call
      response = nil

      Timeout.timeout(timeout) do
        rpc_reply_queue.subscribe(manual_ack: false, block: false, consumer_tag: consumer_tag) do |delivery_info, properties, payload|
          if properties[:correlation_id] == correlation_id
            response = payload
            mutex.synchronize { resource.signal }
          end
        end

        x.publish(payload.to_s, routing_key: queue_name, reply_to: rpc_reply_queue.name,
                  correlation_id: correlation_id)

        mutex.synchronize { resource.wait(mutex) unless response }
        response
      end
    ensure
      reply_channel.consumers[consumer_tag].cancel
    end

    private

    def connection
      @connection.tap do |c|
        c.start unless c.connected?
      end
    end

    def x
      @x ||= channel.default_exchange
    end

    def channel
      @channel ||= connection.create_channel
    end

    def reply_channel
      @reply_channel ||= connection.create_channel
    end

    def rpc_reply_queue
      @rpc_reply_queue ||= reply_channel.queue("", exclusive: true)
    end
  end
end
