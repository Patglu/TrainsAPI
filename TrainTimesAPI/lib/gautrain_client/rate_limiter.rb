# frozen_string_literal: true

module GautrainClient
  # RateLimiter implements a classic sliding window Token Bucket.
  # Standard thread-safety guaranteed via an explicit Mutex monitor.
  class RateLimiter
    @buckets = {}
    @monitor = Mutex.new

    # Evaluates rate boundaries. If threshold exceeded, returns a hash containing
    # rate statistics, otherwise deducts a token and returns metrics.
    def self.throttle!(key, limit: 60, period: 60)
      @monitor.synchronize do
        now    = Time.now.to_f
        bucket = @buckets[key] ||= { tokens: limit.to_f, last_seen: now }

        # Calculate progressive token regeneration
        elapsed = now - bucket[:last_seen]
        regen   = elapsed * (limit.to_f / period)
        bucket[:tokens] = [limit.to_f, bucket[:tokens] + regen].min
        bucket[:last_seen] = now

        if bucket[:tokens] >= 1.0
          bucket[:tokens] -= 1.0
          { allowed: true, remaining: bucket[:tokens].floor, reset_in: (period - elapsed).clamp(0, period).round }
        else
          { allowed: false, remaining: 0, reset_in: [1, (period - elapsed).round].max }
        end
      end
    end

    # Utility method to clear rate cache between tests.
    def self.clear!
      @monitor.synchronize { @buckets.clear }
    end
  end
end