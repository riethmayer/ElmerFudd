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

def rabbitmq_url
  ENV.fetch('RABBITMQ_URL', 'amqp://localhost:5672')
end

def get_new_connection(url: rabbitmq_url, auto_start: true)
  Bunny.new(url, logger: NullLoger.new).tap do |connection|
    connection.start if auto_start
  end
end

def remove_queue(queue_name)
  conn = get_new_connection
  channel = conn.channel
  channel.queue(queue_name).delete
rescue Bunny::PreconditionFailed
  channel = conn.channel
  channel.queue(queue_name, durable: true).delete
ensure
  conn.close
end

def assert_always(timeout = 0.5, &condition)
  Timeout.timeout(timeout) do
    loop { assert condition.call }
  end rescue Timeout::Error
end
