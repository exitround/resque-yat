module Resque
  class Job

    attr_accessor :rate_limit_tx

    def perform_with_limiter
      return perform_without_limiter unless is_rate_restricted

      Job.current_job = self
      begin
        @consumed_amount = 0
        r = perform_without_limiter
      ensure
        reimburse_rate(self.rate_limit_tx[0].amount - @consumed_amount)
      end
      r
    end
    alias_method :perform_without_limiter, :perform
    alias_method :perform, :perform_with_limiter

    def reimburse_rate(amount)
      raise "Reimburse amount is greater than reserved amount" if amount > self.rate_limit_tx[0].amount
      Resque.rate_limiter.reimburse(self.rate_limit_tx, amount) if amount > 0
    end
    def consume_rate(amount=1, api=nil)
      @consumed_amount += 1
    end

    def is_rate_restricted
      !!rate_limit_tx
    end

    class << self
      attr_accessor :current_job

      def reserve_with_limiter(queue)
        return nil if Resque.size(queue) == 0
        return reserve_without_limiter(queue) unless Resque.rate_limiter.is_restricted(queue)

        rate_limit_tx = Resque.rate_limiter.consume(queue, Resque.reserved_rates[queue] || 1)
        return nil unless rate_limit_tx # return if we exceeded the limit

        job = reserve_without_limiter(queue)
        job.rate_limit_tx = rate_limit_tx if job

        job
      end
      alias_method :reserve_without_limiter, :reserve
      alias_method :reserve, :reserve_with_limiter
    end
  end
end
