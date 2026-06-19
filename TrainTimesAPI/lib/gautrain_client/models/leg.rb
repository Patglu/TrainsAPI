# frozen_string_literal: true

module GautrainClient
  module Models
    # Leg represents a single segment of a journey on one vehicle.
    # A direct Rosebank → Sandton trip has one rail leg.
    # A trip involving a bus transfer might have two or three legs.
    #
    # Fare fields are FLATTENED onto the leg (no nested fare object)
    # because our API contract exposes them that way, and keeping the
    # internal shape consistent with the external shape eliminates
    # a translation step in to_h.
    #
    # NOTE: Struct attributes are defined here, methods added in the
    # reopened class below. Never put methods inside Struct.new do...end —
    # constants resolve against the anonymous struct scope, not
    # GautrainClient::Models, causing NameError at runtime.
    Leg = Struct.new(
      :id,               # UUID from upstream
      :mode,             # "rail" or "bus" (always lowercase)
      :line_name,        # e.g. "North - South Line"
      :line_colour,      # CSS hex, e.g. "#b12f23" (converted from ARGB)
      :departure_stop,   # slug, e.g. "rosebank"
      :arrival_stop,     # slug, e.g. "sandton"
      :departure_time,   # ISO 8601 UTC string
      :arrival_time,     # ISO 8601 UTC string
      :duration_seconds, # integer seconds for this leg
      :distance_metres,  # integer metres
      :headsign,         # destination shown on the train front, e.g. "Sandton"
      :carriages,        # integer — 4 or 8. Defaults to 4 if upstream value unparseable.
      :fare_amount_zar,  # float ZAR (upstream returns 30.0, 38.0 etc.)
      :fare_is_peak,     # boolean — true if description == "Peak"
      :fare_product,     # e.g. "Pay-As-You-Go"
      :trip_id,          # vehicle.tripId — kept for future real-time tracking
      :polyline,         # always an Array: [] by default, [[lat,lng],...] if requested
      :waypoints,        # raw waypoints array from upstream
      keyword_init: true
    )

    class Leg
      # Pull in parse_time without duplicating it.
      # `extend` makes TimeParsing's methods available as class methods here.
      extend TimeParsing

      # ── Factory ───────────────────────────────────────────────────────────

      def self.from_hash(h)
        wp_first = h["waypoints"].first
        wp_last  = h["waypoints"].last

        # Station::NAME_TO_SLUG resolves correctly here because this class
        # is reopened inside GautrainClient::Models, so Ruby finds Station
        # in the same module without a fully qualified path.
        departure_stop = Station::NAME_TO_SLUG.fetch(wp_first["stop"]["name"])
        arrival_stop   = Station::NAME_TO_SLUG.fetch(wp_last["stop"]["name"])

        fare = h["fare"]

        new(
          id:               h["id"],
          mode:             h.dig("line", "mode")&.downcase,
          line_name:        h.dig("line", "name"),
          line_colour:      argb_to_css_hex(h.dig("line", "colour")),
          departure_stop:   departure_stop,
          arrival_stop:     arrival_stop,
          departure_time:   parse_time(wp_first["departureTime"]),
          arrival_time:     parse_time(wp_last["arrivalTime"]),
          duration_seconds: h["duration"],
          distance_metres:  h.dig("distance", "value"),
          headsign:         h.dig("vehicle", "headsign"),
          carriages:        parse_carriages(h.dig("vehicle", "designation")),
          fare_amount_zar:  fare.dig("cost", "amount"),
          fare_is_peak:     fare["description"] == "Peak",
          fare_product:     fare.dig("fareProduct", "name"),
          trip_id:          h.dig("vehicle", "tripId"),
          polyline:         [],
          waypoints:        h["waypoints"]
        )
      end

      # ── Instance methods ──────────────────────────────────────────────────

      # Fills the polyline in-place from raw upstream geometry coordinates.
      # Called by the Journeys client after construction when ?include=polylines
      # was requested. The `!` suffix signals mutation.
      #
      # coordinates — upstream [[lng, lat], ...] array (GeoJSON order)
      # We swap each pair to [lat, lng] for iOS/Android map SDK compatibility.
      def fill_polyline!(coordinates)
        self.polyline = coordinates.map { |lng, lat| [lat, lng] }
      end

      # Collects and maps intermediate stations along this specific leg, including
      # their travel duration from the leg's departure station.
      def intermediate_stations
        return [] if waypoints.nil? || waypoints.size <= 2

        # Exclude the very first (origin) and very last (destination) stops of this leg
        intermediate_wps = waypoints[1...-1] || []

        dep_time = Time.parse(departure_time)
        intermediate_wps.map do |wp|
          wp_arr_time_str = wp["arrivalTime"]
          wp_arr_time = Time.parse(wp_arr_time_str).utc if wp_arr_time_str
          duration = wp_arr_time ? (wp_arr_time - dep_time).to_i : 0
          
          stop_name = wp.dig("stop", "name")
          station_slug = Station::NAME_TO_SLUG[stop_name]

          {
            id:               station_slug,
            name:             stop_name,
            arrival_time:     wp_arr_time ? wp_arr_time.iso8601 : nil,
            duration_seconds: duration
          }
        end
      end

      def to_h(include_intermediate: false)
        hash = {
          id:               id,
          mode:             mode,
          line_name:        line_name,
          line_colour:      line_colour,
          departure_stop:   departure_stop,
          arrival_stop:     arrival_stop,
          departure_time:   departure_time,
          arrival_time:     arrival_time,
          duration_seconds: duration_seconds,
          distance_metres:  distance_metres,
          headsign:         headsign,
          carriages:        carriages,
          fare_amount_zar:  fare_amount_zar,
          fare_is_peak:     fare_is_peak,
          fare_product:     fare_product,
          trip_id:          trip_id,
          polyline:         polyline
        }
        if include_intermediate
          hash[:intermediate_stations] = intermediate_stations
        end
        hash
      end

      # ── Private class helpers ─────────────────────────────────────────────

      # Converts upstream ARGB hex ("ffb12f23") to CSS hex ("#b12f23").
      # The first two chars are the alpha channel — we drop them.
      # Returns nil safely if the input is nil (upstream omitted the colour).
      private_class_method def self.argb_to_css_hex(argb)
        return nil if argb.nil?

        "##{argb[2..]}"
      end

      # Parses the integer from upstream's "8 Car" / "4 Car" designation string.
      # Returns 4 as the default if the string is missing or doesn't start with digits.
      # 4 is the safer default — it's the smaller train, so the app won't
      # mislead commuters into expecting an emptier carriage than they'll get.
      private_class_method def self.parse_carriages(designation)
        match = designation.to_s.match(/^(\d+)/)
        match ? match[1].to_i : 4
      end
    end
  end
end