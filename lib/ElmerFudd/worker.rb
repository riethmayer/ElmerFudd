module ElmerFudd
  class Worker
    Message = Struct.new(:delivery_info, :properties, :payload, :route)
    Env = Struct.new(:channel, :logger, :worker_class)
    Route = Struct.new(:exchange_name, :routing_keys, :queue_name)

    class << self
      attr_writer :durable_queues
      def durable_queues; @durable_queues.nil? ? true : @durable_queues; end

      # When set to true, every handler will receive a separate channel
      attr_writer :single_channel
      def single_channel; @single_channel.nil? ? true : @single_channel; end
    end

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
      handlers << TopicHandler.new(route, handler || block, (@filters + filters + [DiscardReturnValueFilter]).uniq,
                                   durable: durable_queues)
    end

    def self.handle_cast(route, filters: [], handler: nil, &block)
      handlers << DirectHandler.new(route, handler || block, (@filters + filters + [DiscardReturnValueFilter]).uniq,
                                    durable: durable_queues)
    end

    def self.handle_call(route, filters: [], handler: nil, &block)
      handlers << RpcHandler.new(route, handler || block, (@filters + filters).uniq,
                                 durable: false)
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
        subscribe_handler(handler)
      end
    end

    private

    def subscribe_handler(handler)
      handler.queue(env).subscribe(manual_ack: true, block: false,
                                   on_cancellation: ->(*) { on_consumer_cancellation(handler) }
                                  ) do |delivery_info, properties, payload|
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

    def on_consumer_cancellation(handler)
      unless self.class.durable_queues
        handler.ensure_that_queue_exists(env)
      end
    end

    def env
      self.class.single_channel ? @env ||= new_env : new_env
    end

    def new_env
      Env.new(new_channel, @logger, self.class)
    end

    def connection
      @connection.tap { |c| c.start unless c.connected? }
    end

    def new_channel
      connection.create_channel.tap do |channel|
        channel.recover_cancelled_consumers!
        channel.tap do |c|
          c.prefetch(@concurrency)
        end
      end
    end
  end
end
