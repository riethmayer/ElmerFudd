module ElmerFudd
  class JsonPublisher < Publisher
    CONTENT_TYPE = 'application/json'

    def notify(topic_exchange, routing_key, payload, content_type: CONTENT_TYPE)
      super(topic_exchange, routing_key, payload.to_json, content_type: content_type)
    end

    def cast(queue_name, payload, content_type: CONTENT_TYPE)
      super(queue_name, payload.to_json, content_type: content_type)
    end

    def call(queue_name, payload, content_type: CONTENT_TYPE, **kwargs)
      JSON.parse(super(queue_name, payload.to_json, content_type: content_type, **kwargs))
    end
  end
end
