class ElmerFudd::FakeProducer
    def initialize(_connection = :no_connection)
      @casts = Hash.new do |hash, queue_name|
        hash[queue_name] = []
      end

      @notifications = Hash.new do |hash, exchange|
        hash[exchange] = Hash.new do |hash, event_name|
          hash[event_name] = []
        end
      end
    end

    def call(queue_name, payload, timeout: 10)
      # not implemented, behaving like other side does not respond
      raise Timeout::Error
    end

    def cast(queue_name, payload)
      @casts[queue_name] << payload
    end

    def notify(exchange, event_name, payload)
      @notifications[exchange][event_name] << payload
    end

    def clear!
      initialize(nil)
    end
  end

  RSpec.configure do |config|
    config.before(:each) do
      ObjectSpace.each_object(ElmerFudd::FakeProducer, &:clear!)
    end
  end

  RSpec::Matchers.define :have_received_cast_on do |queue_name|
    match do |rabbit|
      queue(rabbit).size == (@count || 1)
    end

    chain :with_payload do |payload|
      @payload = payload
    end

    chain :times do |times|
      @count = times
    end

    define_method :queue do |server|
      queue = server.instance_eval { @casts }[queue_name]
      if @payload
        queue = queue.select { |payload| payload == @payload }
      end
      queue
    end

    failure_message do |rabbit|
      if @count
        "expected a message on '#{queue_name}' #{@count} times, but received #{queue(rabbit).size} times"
      else
        "expected a message on '#{queue_name}' 1 time, but received #{queue(rabbit).size} times"
      end
    end

    failure_message_when_negated do |rabbit|
      "expected no message on '#{queue_name}', but receved at least one"
    end

    description do
      "receive a message on '#{queue_name}'"
    end
  end

  RSpec::Matchers.define :have_received_notification_on do |exchange_name, options|
    routing_key = options.fetch(:routing_key)

    match do |rabbit|
      queue(rabbit).size == (@count || 1)
    end

    chain :with_payload do |payload|
      @payload = payload
    end

    chain :times do |times|
      @count = times
    end

    define_method :queue do |server|
      queue = server.instance_eval { @notifications }[exchange_name][routing_key]
      if @payload
        queue = queue.select { |payload| payload == @payload }
      end
      queue
    end

    failure_message do |rabbit|
      if @count
        "expected a message on '#{exchange_name}' with routing key '#{routing_key}' #{@count} times, but received #{queue(rabbit).size} times"
      else
        "expected a message on '#{exchange_name}' with routing key '#{routing_key}' 1 time, but received #{queue(rabbit).size} times"
      end
    end

    failure_message_when_negated do |rabbit|
      "expected no message on '#{queue_name}', but receved at least one"
    end

    description do
      "receive a message on '#{queue_name}'"
    end
  end
