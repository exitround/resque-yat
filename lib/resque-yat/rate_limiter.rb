require 'securerandom'

module RateLimiter

  class RateLimiterError < StandardError; end

  class RateRestriction
    attr_reader :queue_name, :period, :limit
    def initialize(queue_name, period, limit)
      @queue_name = queue_name.to_sym
      @period = period
      @limit = limit
    end
    def hash_key
      [queue_name, period]
    end
    def to_s
      "Rate restriction of #{self.limit} per #{self.period} for queue #{self.queue_name}"
    end
    def counter_name(redis)
      name = redis.get(self.counter_name_key)
      name = create_counter(redis) if name.nil?
      name
    end
    def counter_name_key
      "ratelimiter:#{self.queue_name}-#{self.period}"
    end
    def create_counter(redis)
      name = "ratelimiter:#{self.queue_name}-#{self.period}-#{SecureRandom.uuid}"
      redis.multi do
        redis.psetex(name, self.period * 1000, 0)
        redis.psetex(self.counter_name_key, self.period * 1000, name)
      end
      name
    end
    def consume(redis, amount)
      counter_name = self.counter_name(redis)
      RestrictionTx.new(self, counter_name, amount, redis.incrby(counter_name, amount))
    end
  end

  class RestrictionTx
    attr_reader :counter_name, :amount
    def initialize(restriction, counter_name, amount, result)
      @restriction = restriction
      @counter_name = counter_name
      @amount = amount
      @result = result
    end
    def exceeds_limit
      @result > @restriction.limit
    end
  end

  class Limiter
    def initialize(redis)
      @redis = redis.is_a?(Proc) ? redis : lambda {redis}
      @restrictions = Hash.new {|h, k| h[k] = []}
    end

    def redis
      @redis.call
    end

    def is_restricted(queue_name)
      @restrictions.include?(queue_name.to_sym)
    end

    def add_restriction(restriction)
      duplicate = @restrictions[restriction.queue_name].any? {|r| r.hash_key == restriction.hash_key}
      raise RateLimiterError.new("Already registered restriction for this period") if duplicate

      @restrictions[restriction.queue_name] << restriction
    end

    def consume(queue_name, amount=1)
      queue_name = queue_name.to_sym
      raise RateLimiterError.new("No limits set for queue #{queue_name}") unless is_restricted(queue_name)
      restrictions = @restrictions[queue_name]

      txs = []
      restrictions.each do |restriction|
        txs << (tx = restriction.consume(self.redis, amount))

        if tx.exceeds_limit
          reimburse(txs, amount)
          return nil
        end
      end

      txs
    end

    def reimburse(txs, amount=1)
      txs.each do |tx|
        raise RateLimiterError.new("Rollback amount is greater than transaction amount") if amount > tx.amount
        next unless redis.exists(tx.counter_name)
        redis.decrby(tx.counter_name, amount)
      end
    end
  end
end
