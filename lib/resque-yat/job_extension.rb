module Resque
  class Job

    attr_accessor :rate_limit_txs

    def perform_with_limiter
      return perform_without_limiter unless is_rate_restricted?

      Job.current_job = self
      begin
        @consumed_amount = 0
        r = perform_without_limiter
      ensure
        reimburse_rate(self.rate_limit_txs[0].amount - @consumed_amount)
        Job.current_job = nil # not that this is really required
      end
      r
    end
    alias_method :perform_without_limiter, :perform
    alias_method :perform, :perform_with_limiter

    def reimburse_rate(amount)
      raise "Reimburse amount is greater than reserved amount" if amount > self.rate_limit_txs[0].amount
      Resque.rate_limiter.reimburse(self.rate_limit_txs, amount) if amount > 0
    end
    def consume_rate(amount=1, api=nil)
      @consumed_amount += 1
    end

    def is_rate_restricted?
      !!rate_limit_txs
    end

    class << self
      attr_accessor :current_job

      # This overrides the standard way jobs are pulled out of the queue
      def reserve_with_limiter(queue)
        return nil if Resque.size(queue) == 0 # nothing in the queue
        # Call the original method if no restrictions applied to this queue
        return reserve_without_limiter(queue) unless Resque.rate_limiter.is_restricted?(queue)

        # Try to consume the reserved amount ...
        rate_limit_txs = Resque.rate_limiter.consume(queue, Resque.reserved_rates[queue] || 1)
        # ... return if we exceeded the limit - this is what it's all about
        return nil unless rate_limit_txs

        begin
          job = reserve_without_limiter(queue)
        ensure
          if job
            # Tuck the transaction info onto the job
            job.rate_limit_txs = rate_limit_txs
          else
            # There was an error, or queue is empty - reimburse the reserved amount
            Resque.rate_limiter.reimburse(rate_limit_txs, rate_limit_txs.amount)
          end
        end

        job
      end
      alias_method :reserve_without_limiter, :reserve
      alias_method :reserve, :reserve_with_limiter
    end
  end
end
