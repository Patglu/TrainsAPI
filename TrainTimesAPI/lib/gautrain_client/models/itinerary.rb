# frozen_string_literal: true

module GautrainClient
  module Models
    # Itinerary represents one complete journey option between two stations.
    # It holds one or more Leg objects and computes journey-level aggregates
    # (total fare) that would otherwise have to be computed on the client.
    #
    # Like Leg, methods are defined in a reopened class — not inside
    # Struct.new do...end — to avoid namespace scoping issues.
    Itinerary = Struct.new(
      :id,               # UUID from upstream
      :departure_time,   # ISO 8601 UTC — when the first leg departs
      :arrival_time,     # ISO 8601 UTC — when the last leg arrives
      :duration_seconds, # integer — total trip time (may include wait between legs)
      :distance_metres,  # integer — total distance across all legs
      :legs,             # Array of Leg instances
      :parking_cost_zar, # float or nil — nil means not available, not free
      keyword_init: true
    )

    class Itinerary
      extend TimeParsing

      # ── Factory ───────────────────────────────────────────────────────────

      # parking_cost_zar comes from the TOP-LEVEL upstream response field
      # `oneDayParkingCost`, which is outside each individual itinerary hash.
      # The Journeys client extracts it once and passes it in here so every
      # itinerary in the response carries the same parking cost.
      def self.from_hash(h, parking_cost_zar)
        new(
          id:               h["id"],
          departure_time:   parse_time(h["departureTime"]),
          arrival_time:     parse_time(h["arrivalTime"]),
          duration_seconds: h["duration"],
          distance_metres:  h.dig("distance", "value"),
          legs:             h["legs"].map { |leg_hash| Leg.from_hash(leg_hash) },
          # nil is preserved as nil — 0 would incorrectly imply free parking.
          # The mobile app receives null and can choose whether to show the field.
          parking_cost_zar: parking_cost_zar
        )
      end

      # ── Instance methods ──────────────────────────────────────────────────

      # total_fare_zar is COMPUTED from legs — never stored — so it can
      # never drift out of sync with the actual per-leg fares.
      # TRANSIT ONLY: does not include parking. The mobile app adds parking
      # to the total if the user chose to drive to the station.
      def total_fare_zar
        legs.sum(&:fare_amount_zar)
      end


      # Produces the JSON-ready hash for one journey.
      # legs.map { ... } converts each Leg struct to a plain hash,
      # forwarding the include_intermediate flag.
      def to_h(include_intermediate: false)
        {
          id:               id,
          departure_time:   departure_time,
          arrival_time:     arrival_time,
          duration_seconds: duration_seconds,
          distance_metres:  distance_metres,
          total_fare_zar:   total_fare_zar,
          parking_cost_zar: parking_cost_zar,
          legs:             legs.map { |l| l.to_h(include_intermediate: include_intermediate) }
        }
      end
    end
  end
end