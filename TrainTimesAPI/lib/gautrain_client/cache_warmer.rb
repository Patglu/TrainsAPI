# frozen_string_literal: true

module GautrainClient
  # CacheWarmer pre-fills the journey cache for every valid station pair
  # on server boot. Runs in a background thread so Puma accepts traffic
  # immediately — warm-up does not block the server from starting.
  class CacheWarmer
    # How many pairs to fetch concurrently during warm-up.
    # 10 threads × ~300ms per call ≈ 9 batches × 300ms ≈ ~3 seconds total.
    # Too many threads risks overwhelming Gautrain; 10 is a safe ceiling.
    CONCURRENCY = 10

    def initialize(journeys_client, stations_client)
      @journeys  = journeys_client
      @stations  = stations_client
    end

    # warm! starts the background thread and returns immediately.
    # The thread is daemon: it does not prevent the process from exiting.
    def warm!
      Thread.new do
        Thread.current.name      = "cache-warmer"
        Thread.current[:request_id] = "warmup"
        run_warmup
      rescue => e
        # Never crash the warm-up thread — log and move on.
        # A failed warm-up is not fatal: the cache starts cold and fills
        # on first real requests instead.
        warn "[CacheWarmer] warm-up failed: #{e.message}"
      end
    end

    private

    def run_warmup
      # Fetch all stations first — this also warms the station cache.
      stations = @stations.fetch_all
      slugs    = stations.map(&:id)

      # Build every valid origin→destination pair.
      # `permutation(2)` generates ordered pairs: [a,b] and [b,a] are both included.
      # This gives us all 90 pairs (10 × 9).
      pairs = slugs.permutation(2).to_a
      warn "[CacheWarmer] warming #{pairs.length} route pairs..."

      # Process pairs in batches of CONCURRENCY using threads.
      # `each_slice(n)` splits the array into chunks of n elements.
      pairs.each_slice(CONCURRENCY) do |batch|
        threads = batch.map do |from, to|
          Thread.new do
            Thread.current[:request_id] = "warmup"
            @journeys.fetch(origin_slug: from, destination_slug: to)
          rescue => e
            # One failed pair does not abort the entire warm-up.
            warn "[CacheWarmer] #{from}→#{to} failed: #{e.message}"
          end
        end
        # Wait for all threads in this batch before starting the next.
        # This keeps concurrency bounded — never more than CONCURRENCY
        # simultaneous upstream calls at any moment.
        threads.each(&:join)
      end
      warn "[CacheWarmer] complete."
    end
  end
end