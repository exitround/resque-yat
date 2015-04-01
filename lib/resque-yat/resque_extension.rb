module Resque
  class << self
    def rate_limiter
      @limiter ||= RateLimiter::Limiter.new(lambda{Resque.redis})
    end
    def reserved_rates
      @reserved_rates ||= {}
    end
  end
end