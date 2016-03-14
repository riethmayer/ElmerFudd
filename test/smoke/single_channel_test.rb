require 'test_helper'

class SingleChannelTest < MiniTest::Test
  include RabbitHelper
  TEST_QUEUE = "test.ElmerFudd.cast"
  TEST_QUEUE_2 = "test.ElmerFudd.cast"

  class TestWorker < ElmerFudd::Worker
    default_filters ElmerFudd::JsonFilter
    self.single_channel = false

    handle_cast(Route(TEST_QUEUE)) do |_env, message|
      if delay = message.payload["delay"]
        sleep delay
      end

      $responses << message.payload["message"]
    end

    handle_cast(Route(TEST_QUEUE_2)) do |_env, message|
      if delay = message.payload["delay"]
        sleep delay
      end

      $responses << message.payload["message"]
    end
  end

  def teardown
    remove_queue TEST_QUEUE
    remove_queue TEST_QUEUE_2
    super
  end

  def test_basic_cast
    start_worker TestWorker
    @publisher.cast TEST_QUEUE, message: "hello1", delay: 0.9
    @publisher.cast TEST_QUEUE_2, message: "hello2", delay: 0.9

    Timeout.timeout(1) do
      assert_equal %w(hello1 hello2), [$responses.pop, $responses.pop].sort
    end
  end
end
