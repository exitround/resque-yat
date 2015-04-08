# RateLimiter library was designed to be used by the resque-yat gem to help it track
#  third party API usage rates inside resque queues.
# The typical flow is as follows:
#   1) +RateRestriction+ object is created given the name of the queue and the rate limit
#       that must be applied to it. The rate is expressed as the period and limit, e.g.
#       period: 1 hour, limit: 100 calls.
#   2) The +RateRestriction+ object is added to the Limiter object. The Limiter object
#       is usually used as a singleton, as it most likely to keep track of all rates in
#       your project.
#   3) The +consume+ metod method is called to tell the limiter that there is an intent
#       to make a certain number of API calls. If the rate is exceeded, the +consume+ will
#       return nil and you know you can't make that call. Otherwise a 'transaction' object
#       is returned that could be used later to 'reimburse' the rate (for explanation see below).
#
# RateLimiter implements the "reimburse" pattern. It is useful when you don't know
#  upfront exactly how many API calls will be made by your unit of work (say, resque task).
#  So, you 'consume' what you think is the maximum number of calls could be made, but
#  'reimburse' the number of unused ones.
#
# Note that although this library was designed to help limit API rates inside resque tasks,
# it has no dependency on resque and can be used whenever rate limiting is needed.

require 'securerandom'

module RateLimiter

  class RateLimiterError < StandardError; end

  # Represents a rate restriction.
  #   +queue_name+ - resque queue name. Strictly saying it doesn't have to be a queue name,
  #       can be anything that groups different rate limits together.
  #   +perio+ - period in seconds
  #   +limit+ - limit imposed on the given queue per given period
  #
  # Each restriction creates a counter in Redis with a TTL applied to it.
  class RateRestriction
    attr_reader :queue_name, :period, :limit
    def initialize(queue_name, period, limit)
      @queue_name = queue_name.to_sym
      @period = period
      @limit = limit
    end

    def to_s
      "Rate restriction of #{self.limit} per #{self.period} for queue #{self.queue_name}"
    end

    # This Redis key contains the name of the counter key. It's derived from the queue attributes.
    def counter_name_key
      "ratelimiter:#{self.queue_name}-#{self.period}"
    end

    def consume(redis, amount)
      new_amount = nil
      counter_name = nil

      mr = redis.watch(self.counter_name_key) do
        counter_name = redis.get(self.counter_name_key)
        if counter_name.nil? # counter doesn't exist
          counter_name = "ratelimiter:#{self.queue_name}-#{self.period}-#{SecureRandom.uuid}"
          new_amount = create_counter(redis, counter_name, amount)
        else
          new_amount = modify_counter(redis, counter_name, amount)
        end
      end

      return nil if new_amount.nil?
      RestrictionTx.new(self, counter_name, amount, new_amount)
    end

    def reimburse(redis, tx, amount)
      redis.watch(self.counter_name_key) do
        modify_counter(redis, tx.counter_name, -amount)
      end
    end

    def create_counter(redis, counter_name, amount)
      mr = redis.multi do
        # Set the counter name key
        redis.setex(self.counter_name_key, self.period, counter_name)
        # Set the counter initial value. Both are set to expire at the end of the period.
        redis.setex(counter_name, self.period, amount)
      end
      return mr && amount
    end

    def modify_counter(redis, counter_name, amount)
      mr = redis.multi do
        redis.incrby(counter_name, amount)
        redis.ttl(counter_name)
      end
      return nil if mr.nil?

      new_amount, ttl = mr
      if ttl < 0
        # The counter has no expiration on it,
        # which mean it had expired and INCRBY just created it.
        # We need to delete it and ignore this transaction
        redis.del(counter_name)
        return nil
      end

      new_amount
    end
  end

  # Represents a counter transaction.
  class RestrictionTx
    attr_reader :restriction, :counter_name, :amount
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

  # Represents a central object that keeps track of rate limits for one or more queues.
  class Limiter
    # Initializes the limiter
    # +redis+ - either a redis connection or a Proc that returns Redis connection
    def initialize(redis)
      @redis = redis.is_a?(Proc) ? redis : lambda {redis}
      @restrictions = Hash.new {|h, k| h[k] = []}
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
      @restrictions[restriction.queue_name].delete_if {|r| r.period == restriction.period}
      @restrictions[restriction.queue_name] << restriction
    end

    # 'Consumes' the rate, or, in other words, specifies that the a number
    # of calls will be made by a task in the queue.
    def consume(queue_name, amount=1)
      queue_name = queue_name.to_sym
      raise RateLimiterError.new("No limits set for queue #{queue_name}") unless is_restricted?(queue_name)
      restrictions = @restrictions[queue_name]

      # Go increment counters for all limits of the queue
      txs = []
      restrictions.each do |restriction|
        tx = restriction.consume(self.redis, amount)
        txs << tx if tx

        if tx.nil? || tx.exceeds_limit
          # One of the transactions exceeded the limit, roll them all back
          reimburse(txs, amount)
          return nil
        end
      end

      txs
    end

    # 'Reimburses' the rate. If a task made fewer calls than it claimed earlier by calling the
    # +consume+ method, calling this method allows to tell the Limiter how many calls were NOT made.
    # It helps to keep the rate consumption more precisely.
    def reimburse(txs, amount=1)
      txs.each do |tx|
        raise RateLimiterError.new("Rollback amount is greater than transaction amount") if amount > tx.amount
        tx.restriction.reimburse(redis, tx, amount)
      end
    end
  end
end
