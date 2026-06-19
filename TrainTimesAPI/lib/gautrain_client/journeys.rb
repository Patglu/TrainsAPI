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

    def fetch_arrive_by(origin_slug:, destination_slug:, arrive_by:, include_polylines: false)
      arrive_by_time = Time.parse(arrive_by).getlocal("+02:00")
      # Start fetching from 2 hours before the requested arrive_by time
      start_time = arrive_by_time - (2 * 3600)

      ttl = TTLResolver.for_journeys
      key = cache_key(origin_slug, destination_slug, "arrive_by_#{arrive_by}", include_polylines)

      @cache.fetch(key, ttl: ttl) do
        all_itineraries = []
        as_of = nil

        # 1. Fetch initial page
        first_page = fetch_from_upstream(
          origin_slug: origin_slug,
          destination_slug: destination_slug,
          after_timestamp: nil,
          requested_time: start_time.iso8601,
          include_polylines: include_polylines
        )

        current_itineraries = first_page[:itineraries]
        all_itineraries.concat(current_itineraries)
        as_of = first_page[:as_of]

        # 2. Paginate forward until we hit trains arriving AFTER arrive_by
        loop do
          break if current_itineraries.empty?

          # If the last train in the current page arrives after our target, we have crossed the boundary
          last_train_arrival = Time.parse(current_itineraries.last.arrival_time).getlocal("+02:00")
          break if last_train_arrival > arrive_by_time

          # Otherwise, fetch the next page using the departure time of the last train
          last_departure = current_itineraries.last.departure_time
          
          # To ensure we step strictly forward, we increment the cursor slightly
          next_cursor = (Time.parse(last_departure) + 1).utc.iso8601

          next_page = fetch_from_upstream(
            origin_slug: origin_slug,
            destination_slug: destination_slug,
            after_timestamp: next_cursor,
            requested_time: nil,
            include_polylines: include_polylines
          )

          current_itineraries = next_page[:itineraries]
          break if current_itineraries.empty?
          all_itineraries.concat(current_itineraries)
        end

        # 3. Filter out trains that arrive after arrive_by
        valid_itineraries = all_itineraries.select do |iti|
          Time.parse(iti.arrival_time).getlocal("+02:00") <= arrive_by_time
        end

        # 4. Return the last 5 trains (or fewer if we hit the start of the day)
        { itineraries: valid_itineraries.last(5), as_of: as_of }
      end
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
      # Gautrain API operates on local South Africa Standard Time (SAST, UTC+2).
      # We must convert the UTC timestamp into SAST (+02:00) before sending.
      if after_timestamp
        params["earliestDeparture"] = Time.parse(after_timestamp).getlocal("+02:00").iso8601
      end

      # earliestArrival allows querying from a specific future time.
      if requested_time
        params["earliestArrival"] = Time.parse(requested_time).getlocal("+02:00").iso8601
      end

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
