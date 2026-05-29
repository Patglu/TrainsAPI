# frozen_string_literal: true

require "time"

module GautrainClient
  class Journeys
    ROUTE_PATH  = "/commuter/route"
    EXTEND_PATH = "/commuter/timetable/extend"

    # stations_client — a GautrainClient::Stations instance.
    # The Journeys client now owns coordinate resolution internally,
    # so callers pass station slugs only — no raw coordinates.
    # The stations_client's in-memory cache means lookups are free
    # after the first network call.
    def initialize(http_client, stations_client)
      @http_client     = http_client
      @stations_client = stations_client
      @cache           = CacheStore.new
    end

    def fetch(origin_slug:, destination_slug:, after_timestamp: nil,
              requested_time: nil, include_polylines: false)
      if after_timestamp
        value = fetch_from_upstream(origin_slug: origin_slug,
                                    destination_slug: destination_slug,
                                    after_timestamp: after_timestamp,
                                    requested_time: requested_time,
                                    include_polylines: include_polylines)

        return CacheStore::Result.new(value: value, status: "live_pagination",
                                      cached_at: Time.now, ttl_seconds: 0)
      end

      # TTL is resolved dynamically — peak hours get 15s, off-peak 60s, weekends 120s.
      ttl = TTLResolver.for_journeys
      key = cache_key(origin_slug, destination_slug, after_timestamp, include_polylines)
      @cache.fetch(key, ttl: ttl) do
        # This block only runs on a real cache miss.
        fetch_from_upstream(origin_slug: origin_slug,
                            destination_slug: destination_slug,
                            after_timestamp: after_timestamp,
                            requested_time: requested_time,
                            include_polylines: include_polylines)
      end
      # Returns a CacheStore::Result — the route layer reads .value and .status.
    end

    private

    def fetch_from_upstream(origin_slug:, destination_slug:, after_timestamp:,
                            requested_time:, include_polylines:)
      origin      = station_for_slug!(origin_slug)
      destination = station_for_slug!(destination_slug)
      params      = build_params(origin: origin, destination: destination,
                                 after_timestamp: after_timestamp,
                                 requested_time: requested_time,
                                 include_polylines: include_polylines)
      endpoint    = after_timestamp ? EXTEND_PATH : ROUTE_PATH
      upstream    = @http_client.get(endpoint, params)
      parking     = upstream["oneDayParkingCost"]
      itineraries = upstream["itineraries"].map { |r| Models::Itinerary.from_hash(r, parking) }
      populate_polylines!(itineraries, upstream["itineraries"]) if include_polylines
      { itineraries: itineraries, as_of: upstream["time"] }
    end

    # Generates a unique string key to represent the cache entry.
    # Translates to a format like: "origin:destination:after_timestamp:include_polylines"
    # Example: "rosebank:sandton::false"
    def cache_key(origin, destination, after_timestamp, include_polylines)
      "#{origin}:#{destination}:#{after_timestamp}:#{include_polylines}"
    end

    # Looks up a Station by slug from the cached station list.
    # Raises KeyError with a clear message if the slug is unrecognised.
    def station_for_slug!(slug)
      station = @stations_client.fetch_all.find { |s| s.id == slug }
      raise KeyError, "Unknown station slug: '#{slug}'" unless station

      station
    end

    # Builds the upstream query parameter hash.
    # Coordinates come directly from the Station objects — the caller
    # no longer has to know about lat/lng at all.
    def build_params(origin:, destination:, after_timestamp:, requested_time:, include_polylines:)
      params = {
        "orgLng"          => origin.longitude,
        "orgLat"          => origin.latitude,
        "dstLng"          => destination.longitude,
        "dstLat"          => destination.latitude,
        "publicOperators" => "",
        "isParking"       => "true",    # always true — gives us oneDayParkingCost
        "isImmutable"     => "false",
        "isGeometryReturned" => include_polylines ? "true" : "false"
      }

      # earliestDeparture is the pagination cursor — present on /extend calls only.
      params["earliestDeparture"] = after_timestamp if after_timestamp

      # earliestArrival allows querying from a specific future time.
      params["earliestArrival"] = requested_time if requested_time

      params
    end

    # Fills polyline data on each leg by correlating parsed itineraries
    # with the raw upstream response. We iterate in parallel by index —
    # safe because both arrays always have the same length and ordering.
    def populate_polylines!(itineraries, raw_itineraries)
      itineraries.each_with_index do |itinerary, i|
        raw_legs = raw_itineraries[i]["legs"]
        itinerary.legs.each_with_index do |leg, j|
          coords = raw_legs[j].dig("geometry", "coordinates")
          leg.fill_polyline!(coords) if coords
        end
      end
    end
  end
end
