module ElmerFudd
  class DirectHandler
    include Filter
    attr_reader :route
    attr_accessor :call_reply_content_type

    def initialize(route, callback, filters, options)
      @route = route
      @callback = callback
      @filters = filters
      @durable = options.fetch(:durable)
      @call_reply_content_type = ElmerFudd::DEFAULT_CONTENT_TYPE
      initialize_filters
    end

    def queue(env)
      ensure_that_queue_exists(env)
      env.channel.queue(@route.queue_name, durable: @durable, exclusive: is_exclusive_queue).tap do |queue|
        unless @route.exchange_name == ""
          Array(@route.routing_keys).each do |routing_key|
            queue.bind(exchange(env), routing_key: routing_key)
          end
        end
        @route.queue_name = queue.name
      end
    end

    def ensure_that_queue_exists(env)
      env.channel.queue_declare(@route.queue_name, durable: @durable, exclusive: is_exclusive_queue)
    end

    def exchange(env)
      env.logger.debug "ElmerFudd Handler.exchange queue_name: #{@route.queue_name}, exchange_name: #{@route.exchange_name}, filters: #{filters_names}"
      env.channel.direct(@route.exchange_name)
    end

    def call(env, message)
      env.logger.debug "ElmerFudd #{self.class.name}.call (#{object_id}) queue_name: #{@route.queue_name}, exchange_name: #{@route.exchange_name}, filters: #{filters_names}, message: #{message.payload}"
      call_next(env, message, @filters + [@callback])
    end

    private

    def initialize_filters
      @filters.select { |filter| filter.respond_to?(:setup) }.
        each { |filter| filter.setup(self) }
    end

    def filters_names
      @filters.map { |f| f.respond_to?(:name) ? f.name : f.class.name }
    end

    def is_exclusive_queue
      @route.queue_name == ''
    end
  end
end
