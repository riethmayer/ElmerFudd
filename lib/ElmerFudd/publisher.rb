require 'connection_pool'

module ElmerFudd
  class Publisher
    class Exchange
      def initialize(connection)
        @channel = connection.create_channel
        @reply_channel = connection.create_channel
        @direct = @channel.default_exchange
        @topic_x = {}
      end

      attr_reader :direct

      def rpc_reply_queue
        @rpc_reply_queue ||= @reply_channel.queue("", exclusive: true)
      end

      def cancel_reply_consumer(consumer_tag)
        @reply_channel.consumers[consumer_tag].cancel
      end

      def topic(name)
        @topic_x[name] ||= @channel.topic(name)
      end
    end

    def initialize(connection, uuid_service: -> { rand.to_s }, logger: Logger.new($stdout),
                   max_threads: 4)
      @connection = connection
      @logger = logger
      @uuid_service = uuid_service
      @exchange = ConnectionPool.new(size: max_threads, timeout: 3) do
        Exchange.new(connection)
      end
    end

    def notify(topic_exchange, routing_key, payload, content_type: ElmerFudd::DEFAULT_CONTENT_TYPE)
      @exchange.with do |exchange|
        @logger.debug "ElmerFudd: NOTIFY - topic_exchange: #{topic_exchange}, routing_key: #{routing_key}, payload: #{payload}"
        exchange.topic(topic_exchange).publish payload.to_s, routing_key: routing_key, content_type: content_type
      end
      nil
    end

    def cast(queue_name, payload, content_type: ElmerFudd::DEFAULT_CONTENT_TYPE)
      @exchange.with do |exchange|
        @logger.debug "ElmerFudd: CAST - queue_name: #{queue_name}, payload: #{payload}"
        exchange.direct.publish(payload.to_s, routing_key: queue_name, content_type: content_type)
      end
      nil
    end

    def call(queue_name, payload, timeout: 10, content_type: ElmerFudd::DEFAULT_CONTENT_TYPE)
      @exchange.with do |exchange|
        begin
          @logger.debug "ElmerFudd: CALL - queue_name: #{queue_name}, payload: #{payload}, timeout: #{timeout}"
          mutex = Mutex.new
          resource = ConditionVariable.new
          correlation_id = @uuid_service.call
          consumer_tag = @uuid_service.call
          response = nil

          Timeout.timeout(timeout) do
            exchange.rpc_reply_queue.subscribe(manual_ack: false, block: false, consumer_tag: consumer_tag) do |delivery_info, properties, payload|
              if properties[:correlation_id] == correlation_id
                response = payload
                mutex.synchronize { resource.signal }
              end
            end

            exchange.direct.publish(payload.to_s,
                                    content_type: content_type,
                                    routing_key: queue_name, reply_to: exchange.rpc_reply_queue.name,
                                    correlation_id: correlation_id)

            mutex.synchronize { resource.wait(mutex) unless response }
            response
          end
        ensure
          exchange.cancel_reply_consumer(consumer_tag)
        end
      end
    end

    private

    def connection
      @connection.tap do |c|
        c.start unless c.connected?
      end
    end
  end
end
