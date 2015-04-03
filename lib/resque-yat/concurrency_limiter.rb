module ConcurrencyLimiter
  class ConcurrencyRestriction
    attr_reader :queue_name, :limit
    def initialize(queue_name, limit)
      @queue_name = queue_name.to_sym
      @limit = limit
    end

    def to_s
      "Concurrency restriction of #{self.limit} at a time for queue #{self.queue_name}"
    end

    def redis_key
      "concurrencylimiter:counter:#{self.queue_name}"
    end

    def increment(redis)
      result = redis.watch(redis_key) do
        redis.multi do
          redis.incr(redis_key)
        end
      end
      result && result[0]
    end

    def decrement(redis)
      redis.decr(redis_key)
    end
  end
  class Limiter
    # Initializes the limiter
    # +redis+ - either a redis connection or a Proc that returns Redis connection
    def initialize(redis)
      @redis = redis.is_a?(Proc) ? redis : lambda {redis}
      @restrictions = {}
    end

    def redis
      @redis.call
    end

    # Indicates whether the given queue has any rate restrictions
    def is_restricted?(queue_name)
      @restrictions.include?(queue_name.to_sym)
    end

    # Adds a new restriction to the internal collection of restrictions
    def add_restriction(restriction)
      @restrictions[restriction.queue_name] = restriction
    end

    def start_work(queue_name)
      queue_name = queue_name.to_sym
      raise RateLimiterError.new("No concurrency restriction set for queue #{queue_name}") unless is_restricted?(queue_name)
      restriction = @restrictions[queue_name]

      result = restriction.increment(redis)
      # we couldn't increment atomically
      return nil if result.nil?

      # did we exceed the limit?
      if result > restriction.limit
        restriction.decrement(redis)
        return nil
      end

      result
    end

    def end_work(queue_name)
      queue_name = queue_name.to_sym
      raise RateLimiterError.new("No concurrency restriction set for queue #{queue_name}") unless is_restricted?(queue_name)
      restriction = @restrictions[queue_name]
      restriction.decrement(redis)
    end
  end
end