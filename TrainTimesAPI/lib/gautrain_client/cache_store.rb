# frozen_string_literal: true

module GautrainClient
  class CacheStore
    # The result of a cache lookup — carries the value AND its metadata.
    # Using a Struct keeps the interface clean: callers access result.value,
    # result.status, result.age_seconds without digging into a raw hash.
    Result = Struct.new(:value, :status, :cached_at, :ttl_seconds, keyword_init: true)

    def initialize
      @store    = {}
      @monitor  = Monitor.new
      # Per-key mutexes for request coalescing (Section 4).
      # Stored separately from the cache so they persist across TTL expiry.
      @key_mutexes = Hash.new { |h, k| h[k] = Mutex.new }
    end

    # read returns a Result or nil.
    # status: "fresh" = within TTL, "stale" = past TTL but data exists, nil = nothing
    def read(key)
      @monitor.synchronize do
        entry = @store[key]
        return nil unless entry

        status = Time.now <= entry[:expires_at] ? "fresh" : "stale"
        Result.new(
          value:       entry[:value],
          status:      status,
          cached_at:   entry[:cached_at],
          ttl_seconds: entry[:ttl]
        )
      end
    end

    # write stores a value with a TTL and records when it was cached.
    def write(key, value, ttl:)
      now = Time.now
      @monitor.synchronize do
        @store[key] = {
          value:      value,
          cached_at:  now,
          expires_at: now + ttl,
          ttl:        ttl
        }
      end
    end

    # invalidate removes a specific entry — forces a fresh fetch next time.
    def invalidate(key)
      @monitor.synchronize { @store.delete(key) }
    end

    # flush clears all entries. Used in tests between examples.
    def flush
      @monitor.synchronize { @store.clear }
    end

    # mutex_for is used by the coalescing layer (Section 4).
    # Returns a stable Mutex for the given key, creating it if necessary.
    def mutex_for(key)
      @monitor.synchronize { @key_mutexes[key] }
    end

    # fetch is the primary public interface. Callers never call read/write directly.
    # Usage: cache.fetch("my-key", ttl: 30) { expensive_upstream_call() }
    #
    # Returns a Result with status "fresh", "stale", or raises if nothing available.
    def fetch(key, ttl:, &block)
      # ── 1. First check (no lock) ───────────────────────────────────────────
      # Avoid acquiring the key mutex if the cache already has a fresh entry.
      # This is the hot path — almost all calls return here.
      result = read(key)
      return result if result&&result.status == "fresh"

      # ── 2. Acquire the per-key mutex (coalescing point) ───────────────────
      # Only one thread per key gets past here at a time.
      # All others wait at this line until the winning thread releases the mutex.
      mutex_for(key).synchronize do
        # ── 3. Second check (inside lock) ─────────────────────────────────
        # The thread that just acquired the mutex may have WAITED while
        # another thread fetched and wrote. Re-check now — it may be a hit.
        result = read(key)
        return result if result&&result.status == "fresh"

        # ── 4. Real miss — call the block (upstream fetch) ────────────────
        # The block is only executed by one thread, never concurrently.
        begin
          value = block.call
          write(key, value, ttl: ttl)
          # Return a fresh Result directly — avoids a redundant read().
          Result.new(value: value, status: "fresh",
                     cached_at: Time.now, ttl_seconds: ttl)

        rescue GautrainClient::Error
          # ── 5. Upstream failed — stale fallback ──────────────────────────
          # If we have ANY cached entry (even expired), return it as "stale".
          # This keeps the app functional when Gautrain is temporarily down.
          stale = read(key)
          return stale if stale

          # ── 6. Nothing at all — re-raise for the route layer ─────────────
          # The server.rb error handler catches GautrainClient::Error → 502.
          raise
        end
      end
    end
  end
end