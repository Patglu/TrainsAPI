# frozen_string_literal: true

require_relative "cache_store"

module GautrainClient
  # Fetches the list of Gautrain stations from the upstream API.
  # Results are cached in memory so only the first call hits the network.
  class Stations
    # Path on the Gautrain website that returns the station list.
    STATIONS_PATH = "/commuter/stations"

    def initialize(http_client)
      @http_client = http_client
      @cache       = CacheStore.new
    end

    def fetch_all
      # TTL is fixed — stations never change.
      result = @cache.fetch("stations", ttl: 86_400) do
        raw = @http_client.get(STATIONS_PATH)
        raw.map { |h| Models::Station.from_hash(h) }
      end
      # Return just the value — the route layer gets Station objects directly.
      # Cache metadata (status, cached_at) is used by the journeys route.
      result.value
    end
  end
end
