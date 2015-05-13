module ElmerFudd
  class Worker
    Message = Struct.new(:delivery_info, :properties, :payload, :route)
    Env = Struct.new(:channel, :logger, :worker_class)
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

    # Helper allowing to use any method taking hash as a handler
    # def example(text:, **_)
    #  puts text
    # end
    # # then in worker
    # handle_cast(...
    #             handler: payload_as_kwargs(method(:example)))
    # Thanks to usage of **_ in arguments list it will accept
    # any payload contaning 'text' key. Skipping **_ will require
    # listing all payload keys in argument list
    def self.payload_as_kwargs(handler, only: nil)
      lambda do |_env, message|
        symbolized_payload = message.payload.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
        symbolized_payload = symbolized_payload.select { |k,v| Array(only).include?(k) } if only
        handler.call(symbolized_payload)
      end
    end

    def initialize(connection, concurrency: 1, logger: Logger.new($stdout))
      @connection = connection
      @concurrency = concurrency
      @logger = logger
    end

    def start
      self.class.handlers.each do |handler|
        handler.queue(env).subscribe(manual_ack: true, block: false) do |delivery_info, properties, payload|
          message = Message.new(delivery_info, properties, payload, handler.route)
          begin
            handler.call(env, message)
            env.channel.acknowledge(message.delivery_info.delivery_tag)
          rescue Exception => e
            env.logger.fatal("Worker blocked: %s, %s:" % [e.class, e.message])
            e.backtrace.each { |l| env.logger.fatal(l) }
          end
        end
      end
    end

    private

    def env
      @env ||= Env.new(channel, @logger, self.class)
    end

    def connection
      @connection.tap { |c| c.start unless c.connected? }
    end

    def channel
      @channel ||= connection.create_channel.tap { |c| c.prefetch(@concurrency) }
    end
  end
end
