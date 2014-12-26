require "ElmerFudd/version"
require "bunny"
require "thread"

module ElmerFudd
  class Publisher
    def initialize(connection, uuid_service: -> { rand.to_s })
      @connection = connection
      @channel = @connection.create_channel
      @x = @channel.default_exchange
      @rpc_reply_queue = @channel.queue("", exclusive: true)
      @uuid_service = uuid_service
      @topic_x = {}
    end

    def notify(topic_exchange, routing_key, payload)
      @topic_x[topic_exchange] ||= @channel.topic(topic_exchange)
      @topic_x[topic_exchange].publish payload.to_s, routing_key: routing_key
      nil
    end

    def cast(queue_name, payload)
      @x.publish(payload.to_s, routing_key: queue_name)
      nil
    end

    def call(queue_name, payload, timeout: 10)
      mutex = Mutex.new
      resource = ConditionVariable.new
      correlation_id = @uuid_service.call
      consumer_tag = @uuid_service.call
      response = nil
      
      Timeout.timeout(timeout) do
        @rpc_reply_queue.subscribe(block: false, consumer_tag: consumer_tag) do |delivery_info, properties, payload|
          mutex.synchronize {
            if properties[:correlation_id] == correlation_id
              response = payload
              delivery_info.consumer.cancel
              resource.signal
            end
          }
        end
      end
      
      @x.publish(payload.to_s,
                 routing_key: queue_name,
                 reply_to: @rpc_reply_queue.name,
                 correlation_id: correlation_id)
      
      mutex.synchronize {
        resource.wait(mutex) unless response
      }
      
      response
    rescue Timeout::Error
      @channel.consumers[consumer_tag].cancel
      raise
    end
  end

  class JsonPublisher < Publisher
    def notify(topic_exchange, routing_key, payload)
      super(topic_exchange, routing_key, payload.to_json)
    end

    def cast(queue_name, payload)
      super(queue_name, payload.to_json)
    end

    def call(queue_name, payload, **kwargs)
      JSON.parse(super(queue_name, payload.to_json, **kwargs))
    end
  end

  class Worker
    Message = Struct.new(:delivery_info, :properties, :payload, :route)
    Env = Struct.new(:channel, :logger)
    Route = Struct.new(:exchange_name, :routing_keys, :queue_name)

    def self.handlers
      @handlers ||= []
    end

    def self.Route(queue_name, exchange_and_routing_keys = {"" => queue_name})
      exchange, routing_keys = exchange_and_routing_keys.first
      Route.new(exchange, routing_keys, queue_name)
    end

    def self.default_filters(*filters)
      @filters = filters
    end

    def self.handle_event(route, filters: [], handler: nil, &block)
      handlers << TopicHandler.new(route, handler || block, (@filters + filters + [DiscardReturnValueFilter]).uniq)
    end

    def self.handle_cast(route, filters: [], handler: nil, &block)
      handlers << DirectHandler.new(route, handler || block, (@filters + filters + [DiscardReturnValueFilter]).uniq)
    end

    def self.handle_call(route, filters: [], handler: nil, &block)
      handlers << RpcHandler.new(route, handler || block, (@filters + filters).uniq)
    end

    def initialize(connection, concurrency: 1, logger: Logger.new($stdout))
      @connection = connection
      channel = connection.create_channel.tap { |c| c.prefetch(concurrency) }
      @env = Env.new(channel, logger)
    end

    def start
      self.class.handlers.each do |handler|
        handler.queue(@env).subscribe(manual_ack: true, block: false) do |delivery_info, properties, payload|
          message = Message.new(delivery_info, properties, payload, handler.route)
          begin
            handler.call(@env, message)
            @env.channel.acknowledge(message.delivery_info.delivery_tag)
          rescue Exception => e
            @env.logger.fatal("Worker blocked: %s, %s:" % [e.class, e.message])
            e.backtrace.each { |l| @env.logger.fatal(l) }
          end
        end
      end
    end
  end

  module Filter
    def call_next(env, message, filters)
      next_filter, *remainder = filters
      if remainder.empty?
        next_filter.call(env, message)
      else
        next_filter.call(env, message, remainder)
      end
    end
  end

  class DirectHandler
    include Filter
    attr_reader :route

    def initialize(route, callback, filters)
      @route = route
      @callback = callback
      @filters = filters
    end

    def queue(env)
      env.channel.queue(@route.queue_name, durable: true).tap do |queue|
        unless @route.exchange_name == ""
          Array(@route.routing_keys).each do |routing_key|
            queue.bind(exchange(env), routing_key: routing_key)
          end
        end
      end
    end

    def exchange(env)
      env.channel.direct(@route.exchange_name)
    end

    def call(env, message)
      call_next(env, message, @filters + [@callback])
    end
  end

  class TopicHandler < DirectHandler
    def exchange(env)
      env.channel.topic(@route.exchange_name, durable: false, internal: false, autodelete: false)
    end
  end

  class RpcHandler < DirectHandler
    def call(env, message)
      reply(env, message, super)
    end

    def reply(env, original_message, response)
      exchange(env).publish(response.to_s, routing_key: original_message.properties.reply_to,
                            correlation_id: original_message.properties.correlation_id)
    end
  end

  class JsonFilter
    extend Filter
    def self.call(env, message, filters)
      message.payload = JSON.parse(message.payload)
      {result: call_next(env, message, filters)}.to_json
    rescue JSON::ParserError
      env.logger.error "Ignoring invalid JSON: #{message.payload}"
    end
  end

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

  class AirbrakeFilter
    extend Filter
    def self.call(env, message, filters)
      call_next(env, message, filters)
    rescue Exception => e
      Airbrake.notify(e, parameters: {
                        payload: message.payload,
                        queue: message.route.queue_name,
                        exchange_name: message.route.exchange_name,
                        routing_key: message.delivery_info.routing_key,
                        matched_routing_key: message.route.routing_keys
                      })
      raise
    end
  end

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

  class DiscardReturnValueFilter
    extend Filter
    def self.call(env, message, filters)
      call_next(env, message, filters)
      nil
    end
  end

  class RedirectFailedFilter
    include Filter
    def initialize(producer, error_queue, exception: Exception,
                   exception_message_matches: /.*/)
      @producer = producer
      @error_queue = error_queue
      @exception = exception
      @exception_message_matches = exception_message_matches
    end

    def call(env, message, filters)
      call_next(env, message, filters)
    rescue @exception => e
      if e.message =~ @exception_message_matches
        @producer.cast @error_queue, message.payload
      else
        raise
      end
    end
  end

  class RetryFilter
    include Filter

    def initialize(times, exception: Exception,
                   exception_message_matches: /.*/)
      @times = times
      @exception = exception
      @exception_message_matches = exception_message_matches
    end

    def call(env, message, filters)
      retry_num = 0
      begin
        call_next(env, message, filters)
      rescue @exception => e
        if e.message =~ @exception_message_matches && retry_num < @times
          retry_num += 1
          sleep Math.log(retry_num, 2)
          retry
        else
          raise
        end
      end
    end
  end
end
