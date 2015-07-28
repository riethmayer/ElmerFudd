# Be vewwy, vewwy quiet...I'm hunting wabbits! [![Build Status](https://travis-ci.org/bonusboxme/ElmerFudd.svg)](https://travis-ci.org/bonusboxme/ElmerFudd) ![Build status](https://circleci.com/gh/sevos/ElmerFudd.svg?style=shield&circle-token=:circle-token)

![Elmer Fudd](https://raw.githubusercontent.com/bonusboxme/ElmerFudd/master/elmer-fudd.jpg)

# ElmerFudd

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

    gem 'ElmerFudd'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ElmerFudd

## Usage

### Consumer

```ruby
#!/usr/bin/env ruby
# Example app/worker/test_worker.rb in rails

require_relative "../../config/environment"

class TestLogger
  def initialize(stream)
    @stream = stream
  end

  def call(_env, message)
    @stream.puts "[#{Time.now}] received on #{message.delivery_info.routing_key} payload: #{message.payload.inspect}"
  end
end

class TestWorker < ElmerFudd::Worker
  default_filters(ElmerFudd::JsonFilter)

  handle_cast(Route('test.print')) do |env, message|
    puts %{message: #{message.payload["text"]}}
  end

  handle_call(Route('test.ping')) do |env, message|
    %{pong: #{message.payload["text"]}}
  end

  handle_call(Route('test.ping')) do |env, message|
    %{pong: #{message.payload["text"]}}
  end

  handle_event(Route('test.log', 'a_topic_exchange' => 'test.#'),
               handler: TestLogger.new($stdout))
end

if $PROGRAM_NAME == __FILE__
  trap("TERM", "DEFAULT") { exit 0 }
  $connection = Bunny.new
  TestWorker.new($connection, concurrency: 4).start
  loop { sleep(1) }
end
```

### Producer

```ruby
$connection = Bunny.new
$rabbit = ElmerFudd::JsonPublisher.new($connection)

$rabbit.cast('test.print', text: 'hello') # will print "message: hello"

$rabbit.call('test.ping', text: 'echo') #=> "pong: echo"

$rabbit.notify('a_topic_exchange', 'test.log.some.event', count: 1) # will print "[current time here] received on test.log.some.event payload: {count: 1}"
```

### Queue naming

If you want to consume an event in all listening processes (instead of just first available one), pass an empty string as queue name:

```ruby
handle_event(Route('', 'a_topic_exchange' => 'test.some.event'),
               handler: TestLogger.new($stdout))
```

### Filters

Filters allow to mutate an incoming message in consumer before it hits appropiate handler or to modify return value (or handle errors) after the handler finishes its job. You can define default filters which will be applied to all handlers in consumer or activate them on handler level by passing filters list as a param, i.e.:

```ruby
handle_cast(Route('math.divide'),
            filter: [DropFailedFilter.new(exception: ZeroDivisionError)]) do |env, message|
    puts "#{payload['a'] / payload['b']}"
end
```

#### Available filters

* `JsonFilter` - deserializes incoming messages using json and serializes call responses to json
* `DropFailedFilter.new(exception: Exception, exception_message_matches: /.*/)` - ignore the message if handler raises matching exception
* `AirbrakeFilter` - notify airbrake if handler raises exception and reraises it in filter chain
* `ActiveRecordConnectionPoolFilter` - allows to use worker with higher concurrency (takes a connection from pool for each message)
* `RetryFilter.new(2, exception: Exception, exception_message_matches: /.*/)` - retries 2 times if handler raises a matching exception


## Contributing

1. Fork it ( http://github.com/<my-github-username>/ElmerFudd/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

** Credits
- [Artur Roszczyk](https://github.com/sevos)
- [Andrzej Sliwa](https://github.com/andrzejsliwa)
- [Andrey Parubets](https://github.com/parubets)
