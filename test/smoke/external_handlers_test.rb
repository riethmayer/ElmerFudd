require 'test_helper'

class ExternalHandlersTest < MiniTest::Test
  TEST_QUEUE = "test.ElmerFudd.cast"

  module Handler
    extend self
    def call(_env, message)
      run(text: message.payload["text"])
    end

    def run(text:, **_ignore_rest_of_the_payload)
      $responses.push text
    end
  end

  class TestWorker1 < ElmerFudd::Worker
    default_filters ElmerFudd::JsonFilter
    handle_cast(Route(TEST_QUEUE), handler: Handler)
  end

  class TestWorker2 < ElmerFudd::Worker
    default_filters ElmerFudd::JsonFilter
    handle_cast(Route(TEST_QUEUE),
                handler: payload_as_kwargs(Handler.method(:run)))
  end

  def setup
    @publisher_connection = get_new_connection
    @publisher = ElmerFudd::JsonPublisher.new(@publisher_connection, logger: NullLoger.new)
    @worker_connection = get_new_connection
    $responses = Queue.new
  end

  def teardown
    @publisher_connection.stop
    @worker_connection.stop
    remove_queue TEST_QUEUE
  end

  def test_external_handler
    TestWorker1.new(@worker_connection, logger: NullLoger.new).tap(&:start)
    @publisher.cast TEST_QUEUE, text: "hello"

    Timeout.timeout(0.5) do
      assert "hello", $responses.pop
    end
  end

  def test_payload_as_kwargs
    TestWorker2.new(@worker_connection, logger: NullLoger.new).tap(&:start)
    @publisher.cast TEST_QUEUE, text: "hello", ignored_param: true

    Timeout.timeout(0.5) do
      assert "hello", $responses.pop
    end
  end
end
