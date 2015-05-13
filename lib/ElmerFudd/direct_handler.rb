module ElmerFudd
  class DirectHandler
    include Filter
    attr_reader :route

    def initialize(route, callback, filters)
      @route = route
      @callback = callback
      @filters = filters
    end

    def queue(env)
      env.channel.queue(@route.queue_name, durable: true, exclusive: is_exclusive_queue).tap do |queue|
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

    private

    def is_exclusive_queue
      @route.queue_name == ''
    end
  end
end
