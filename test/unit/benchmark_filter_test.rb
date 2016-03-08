require 'test_helper'

class BenchmarkFilterTest < MiniTest::Test
  class FakeLogger
    attr_reader :logs

    def initialize
      @logs = Hash.new { |h, key| h[key] = [] }
    end

    def method_missing(log_level, message)
      @logs[log_level.to_sym] << message
    end
  end

  def bm_filter(**kwargs)
    ElmerFudd::BenchmarkFilter.new(**kwargs)
  end

  def env
    Struct.new(:logger).new(@logger)
  end

  def setup
    @logger = FakeLogger.new
  end

  def test_measures_time_of_the_block
    message = OpenStruct.new(route: OpenStruct.new(queue_name: "foo"))
    ElmerFudd::BenchmarkFilter.new.call(env, message, [->(*){ sleep 1 }])
    log_entry = @logger.logs[:info].first
    assert_match /Queue: foo/, log_entry
    assert_match /Wall time: 1\.\d+/, log_entry
  end
end
