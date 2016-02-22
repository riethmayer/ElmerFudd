require 'ElmerFudd'
require 'minitest'
require 'minitest/unit'
require 'minitest/autorun'
require 'minitest/pride'

class NullLoger < Logger
  def initialize(*args)
  end

  def add(*args, &block)
  end
end

module RabbitHelper
  def setup
    super
    @publisher = ElmerFudd::JsonPublisher.new(get_new_connection, logger: NullLoger.new)
    $responses = Queue.new
  end

  def teardown
    sleep 0.1
    rabbit_close_connections
    super
  end

  def rabbitmq_url
    ENV.fetch('RABBITMQ_URL', 'amqp://localhost:5672')
  end

  def get_new_connection(url: rabbitmq_url, auto_start: true)
    Bunny.new(url, logger: NullLoger.new).tap do |connection|
      connection.start if auto_start
      (@rabbit_connections ||= []) << connection
    end
  end

  def remove_queue(queue_name)
    conn = get_new_connection
    channel = conn.channel
    channel.queue(queue_name).delete
  rescue Bunny::PreconditionFailed
    channel = conn.channel
    channel.queue(queue_name, durable: true).delete
  end

  def rabbit_close_connections
    if @rabbit_connections
      @rabbit_connections.each(&:close)
      @rabbit_connections.clear
    end
  end

  def start_worker(worker_class, concurrency: 1, connection: get_new_connection)
    worker_class.new(connection, concurrency: concurrency,
                     logger: NullLoger.new).tap(&:start)
  end
end

def assert_always(timeout = 0.5, &condition)
  Timeout.timeout(timeout) do
    loop { assert condition.call; sleep timeout / 10.0 }
  end rescue Timeout::Error
end
