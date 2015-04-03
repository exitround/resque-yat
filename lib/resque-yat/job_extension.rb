module Resque
  class Job

    attr_accessor :rate_limit_txs

    def is_rate_restricted?
      !!rate_limit_txs
    end

    def is_concurrency_restricted?
      Job.concurrency_limiter.is_restricted?(@queue)
    end

    def consume_rate(amount=1, api=nil)
      @consumed_amount += amount
    end

    def perform_with_limiter
      return perform_without_limiter unless is_rate_restricted? || is_concurrency_restricted?

      begin
        Job.current_job = self
        @consumed_amount = 0

        result = perform_without_limiter

      ensure
        adjust_rate if is_rate_restricted?
        end_work if is_concurrency_restricted?

        Job.current_job = nil # not that this is really required
      end
      result
    end
    alias_method :perform_without_limiter, :perform
    alias_method :perform, :perform_with_limiter

    private

    def adjust_rate
      leftover = self.rate_limit_txs[0].amount - @consumed_amount

      if leftover < 0
        # we overconsumed
        Job.rate_limiter.consume(self.rate_limit_txs[0].restriction.queue_name, -leftover)
      elsif leftover > 0
        # reimburse
        Job.rate_limiter.reimburse(self.rate_limit_txs, leftover)
      end
    end

    def end_work
      Job.concurrency_limiter.end_work(@queue)
    end

    public

    class << self
      attr_accessor :current_job

      def rate_limiter
        @rate_limiter ||= RateLimiter::Limiter.new(lambda{Resque.redis})
      end
      def concurrency_limiter
        @concurrency_limiter ||= ConcurrencyLimiter::Limiter.new(lambda{Resque.redis})
      end
      def reserved_rates
        @reserved_rates ||= {}
      end

      # This overrides the standard way jobs are pulled out of the queue
      def reserve_with_limiter(queue)
        return nil if Resque.size(queue) == 0 # nothing in the queue

        rate_restricted = rate_limiter.is_restricted?(queue)
        concurrency_restricted = concurrency_limiter.is_restricted?(queue)

        # Call the original method and return if no restrictions applied to this queue
        return reserve_without_limiter(queue) unless rate_restricted || concurrency_restricted

        begin
          if concurrency_restricted
            # Try concurrency limit. Return if it's exceeded
            concurrency_limit_tx = concurrency_limiter.start_work(queue)
            return nil unless concurrency_limit_tx
          end

          if rate_restricted
            # Try to consume the reserved amount ...
            rate_limit_txs = rate_limiter.consume(queue, reserved_rates[queue] || 1)
            # ... return if we exceeded the limit - this is what it's all about
            return nil unless rate_limit_txs
          end

          job = reserve_without_limiter(queue)
        ensure
          if job
            # Tuck the transaction info onto the job
            job.rate_limit_txs = rate_limit_txs
          else
            # There was an error, or queue is empty - undo limiters
            rate_limiter.reimburse(rate_limit_txs, rate_limit_txs[0].amount) if rate_limit_txs
            concurrency_limiter.end_work(queue) if concurrency_limit_tx
          end
        end

        job
      end
      alias_method :reserve_without_limiter, :reserve
      alias_method :reserve, :reserve_with_limiter
    end
  end
end
