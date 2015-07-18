require 'test_helper'

class CallTest < MiniTest::Test
  TEST_QUEUE = "test.ElmerFudd.call"

  class TestWorker < ElmerFudd::Worker
    default_filters ElmerFudd::JsonFilter

    handle_call(Route(TEST_QUEUE)) do |_env, message|
      raise "unexpected error" if message.payload["raise"]
      if delay = message.payload["delay"]
        sleep delay
      end

      message.payload["message"]
    end
  end

  def setup
    @publisher_connection = get_new_connection
    @publisher = ElmerFudd::JsonPublisher.new(@publisher_connection, logger: NullLoger.new)
    @worker_connection = get_new_connection
  end

  def teardown
    @publisher_connection.stop
    remove_queue TEST_QUEUE
  end

  def test_call_returns_the_value_from_worker
    TestWorker.new(@worker_connection, logger: NullLoger.new).tap(&:start)
    assert_equal({"result" => "hello"},
                 @publisher.call(TEST_QUEUE, message: "hello"))
  end

  def test_call_timeouts_if_worker_time_outs
    TestWorker.new(@worker_connection, logger: NullLoger.new).tap(&:start)
    response = nil
    assert_raises Timeout::Error do
      # The default timeout is different and greater than 0
      response = @publisher.call(TEST_QUEUE, {message: "hello", delay: 2},
                                 timeout: 0.5)
      assert_nil response
    end
  end

  def test_call_timeouts_if_worker_crashes
    TestWorker.new(@worker_connection, logger: NullLoger.new).tap(&:start)
    response = nil
    assert_raises Timeout::Error do
      # The default timeout is different and greater than 0
      response = @publisher.call(TEST_QUEUE, {message: "hello", raise: true},
                                 timeout: 0.5)
      assert_nil response
    end
  end
end
