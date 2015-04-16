module ElmerFudd
  class JsonPublisher < Publisher
    def notify(topic_exchange, routing_key, payload)
      super(topic_exchange, routing_key, payload.to_json)
    end

    def cast(queue_name, payload)
      super(queue_name, payload.to_json)
    end

    def call(queue_name, payload, **kwargs)
      JSON.parse(super(queue_name, payload.to_json, **kwargs))
    end
  end
end
