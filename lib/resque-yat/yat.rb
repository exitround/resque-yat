# Here is an example how to limit rates with resque-yat:
#
#   class MyQueueClass
#     @queue = :MyTestQueue
#
#     # Specify rates for the queue
#     # This limits the queue to 25 calls per hour or 2500 calls per day
#     # It is assumed that the task will make at most 5 calls that
#     # count against the limit.
#     extend Resque::Plugins::Yat
#     limit_rate 1.hour => 25, 1.day => 2500, :reserved_rate => 5
#
#     def self.perform
#       # Call the api that we want to rate limit.
#       some_data = some_third_party.call_api()
#       # Every time we make a call, we let the throttler know about it.
#       consume_rate
#     end
#   end
#
# In the example above, tasks from the 'MyTestQueue' will only be processed if
# at least 5 calls can be made without exceeding the API limit (as specified by :reserved_rate).
# The task will actually make one call (specified by calling consume_rate),
# therefore once the task is finished, four calls would be automatically 'reimbursed'
#


module Resque::Plugins
  module Yat
    def self.consume_rate(amount=1, api=nil)
      Resque::Job.current_job.consume_rate(amount, api) if Resque::Job.current_job
    end

    module PerformerClassExtension
      def restrictions
        @restrictions ||= []
      end
      def reserved_rate
        @reserved_rate ||= 1
      end

      # Call this method to let resque-yat that a call was made that
      # should count against the rate limit.
      def consume_rate(amount=1, api=nil)
        Yat.consume_rate(amount, api)
      end

      def limit_rate(opts = {})
        opts = opts.clone
        queue_name = Resque.queue_from_class(self).to_s

        if opts.include?(:api)
          queue_name += opts[:api].to_s
          opts.delete(:api)
        end
        if opts.include?(:reserved_rate)
          @reserved_rate = opts[:reserved_rate].to_i
          Resque.reserved_rates[queue_name] = @reserved_rate
          opts.delete(:reserved_rate)
        end

        opts.each do |o|
          restriction = RateLimiter::RateRestriction.new(queue_name, o[0], o[1])
          self.restrictions << restriction
          Resque.rate_limiter.add_restriction(restriction)
        end
      end
    end

    def self.extended(cls)
      cls.extend(PerformerClassExtension)
    end
  end
end
