require 'benchmark'

module ElmerFudd
  class BenchmarkFilter
    include Filter

    def initialize(printer: method(:default_printer),
                   benchmark: Benchmark)
      @printer = printer
      @benchmark = benchmark
    end

    def call(env, message, filters)
      result = nil
      exception = nil

      bm = @benchmark.measure do
        begin
          result = call_next(env, message, filters)
        rescue Exception => e
          exception = e
        end
      end
      @printer.call(bm, exception, message.route, env.logger)
      exception.nil? ? result : raise(exception)
    end

    private

    def default_printer(bm, exception, route, logger)
      if exception.nil?
        logger.info "ElmerFudd::Benchmark Queue: #{route.queue_name} | Success | Total CPU: #{bm.total} | Wall time: #{bm.real}"
      else
        logger.info "ElmerFudd::Benchmark Queue: #{route.queue_name} | Exception: #{exception.class.name} | Total CPU: #{bm.total} | Wall time: #{bm.real}"
      end
    end
  end
end
