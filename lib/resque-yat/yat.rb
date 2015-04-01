require 'resque'

module Resque::Plugins
  module Yat
    module PerformerClassExtension
      def restrictions
        @restrictions ||= []
      end
      def reserved_rate
        @reserved_rate ||= 1
      end

      def rated_call(api=nil)
        Resque::Job.current_job.consume_rate(api)
      end

      def limit_rate(opts = {})
        opts = opts.clone
        queue_name = Resque.queue_from_class(self).to_s

        if opts.include?(:api)
          queue_name += opts[:api].to_s
          opts.delete(:api)
        end
        if opts.include?(:reserved_rate)
          Resque.reserved_rates[queue_name] = opts[:reserved_rate].to_i
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
