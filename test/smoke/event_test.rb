require 'test_helper'

class EventTest < MiniTest::Test
  TEST_QUEUE_1 = "test.ElmerFudd.event.all"
  TEST_QUEUE_2 = "test.ElmerFudd.event.high_prio"

  class TestWorker < ElmerFudd::Worker
    default_filters ElmerFudd::JsonFilter

    handle_event(Route(TEST_QUEUE_1, "x_topic" => "event.#")) do |_env, message|
      $responses.push message.payload["message"]
    end

    handle_event(Route(TEST_QUEUE_2, "x_topic" => "event.high.*")) do |_env, message|
      $high_prio_responses.push message.payload["message"]
    end
  end

  def setup
    @publisher_connection = get_new_connection
    @publisher = ElmerFudd::JsonPublisher.new(@publisher_connection, logger: NullLoger.new)
    @worker_connection = get_new_connection

    $responses = Queue.new
    $high_prio_responses = Queue.new
    TestWorker.new(@worker_connection, logger: NullLoger.new).tap(&:start)
  end

  def teardown
    channel = @publisher_connection.channel
    channel.topic("x_topic").delete
    @publisher_connection.stop
    @worker_connection.stop
    remove_queue TEST_QUEUE_1
    remove_queue TEST_QUEUE_2
  end

  def test_notify_matches_event_name
    @publisher.notify "x_topic", "event.some_event", message: "hello"

    Timeout.timeout(0.5) { assert_equal "hello", $responses.pop }
    assert_always { $high_prio_responses.empty? }
  end

  def test_message_can_match_multiple_queues
    @publisher.notify "x_topic", "event.high.some_event", message: "hello2"

    Timeout.timeout(0.5) { assert_equal "hello2", $responses.pop }
    Timeout.timeout(0.5) { assert_equal "hello2", $high_prio_responses.pop }
  end

end
