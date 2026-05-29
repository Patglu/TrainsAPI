# frozen_string_literal: true

require "set"  # Set is stdlib but needs explicit require in Ruby 3.2+

module GautrainClient
  module Models
    # Station represents one physical Gautrain station.
    # There are exactly 10. The list is treated as static — Gautrain
    # has not added a station since 2011.
    #
    # We define the struct attributes first, then REOPEN the class below
    # to add constants and methods. This avoids the Struct.new do...end
    # scoping trap where constants resolve against the anonymous struct
    # rather than GautrainClient::Models::Station.
    Station = Struct.new(
      :id,        # slug, e.g. "rosebank" — our canonical identifier
      :name,      # human-readable, e.g. "OR Tambo"
      :latitude,  # float, e.g. -26.14622
      :longitude, # float, e.g. 28.04451
      :modes,     # array of lowercase strings, e.g. ["bus", "rail"]
      keyword_init: true
    )

    class Station
      # ── Static lookup tables ──────────────────────────────────────────────
      #
      # These constants are the single source of truth for the slug ↔ upstream
      # ID mapping. Every other file that needs this mapping reads it from here.
      # .freeze prevents accidental mutation.

      # Gautrain's opaque station IDs → our human-readable slugs.
      SLUG_BY_UPSTREAM_ID = {
        "l99Qqgtul0imZWPofLfzyA" => "centurion",
        "_rkqSHvRE0Scvbcsuy0EVw" => "hatfield",
        "GqW6XDaSsk-6eFTiiRt46A" => "marlboro",
        "ucS8WAkRbkiKUDPHCVxSYA" => "midrand",
        "nsg0gaT4zkWiYlX31c18Ew" => "or-tambo",
        "hIhX2tikw0SinKacAKV6YQ" => "park",
        "hv_Bf87q50W48rwIUwqCTg" => "pretoria",
        "nOZz7-NPrEmB2KacALquAA" => "rhodesfield",
        "9HM2lKh9F0mYQfRSO6CGCw" => "rosebank",
        "jXU-OlvxukW8wfc7JeVeXw" => "sandton"
      }.freeze

      # Reverse lookup: slug → upstream ID. Built from SLUG_BY_UPSTREAM_ID so
      # the two can never drift apart. Used by the Journeys client when it
      # needs to verify or reference an upstream station ID.
      UPSTREAM_ID_BY_SLUG = SLUG_BY_UPSTREAM_ID.invert.freeze

      # Upstream waypoint stop names → slugs. The name in a leg's waypoint
      # ("Rosebank") is not the same field as the upstream station ID — we
      # need a separate name map. Defined here so it stays next to the ID map.
      NAME_TO_SLUG = {
        "Centurion"   => "centurion",
        "Hatfield"    => "hatfield",
        "Marlboro"    => "marlboro",
        "Midrand"     => "midrand",
        "OR Tambo"    => "or-tambo",
        "Park"        => "park",
        "Pretoria"    => "pretoria",
        "Rhodesfield" => "rhodesfield",
        "Rosebank"    => "rosebank",
        "Sandton"     => "sandton"
      }.freeze

      # Fast O(1) membership check. Used in the route layer to validate
      # that a client-supplied slug is one we know about.
      VALID_SLUGS = SLUG_BY_UPSTREAM_ID.values.to_set.freeze

      # ── Factory method ────────────────────────────────────────────────────

      # Builds a Station from a raw hash returned by /commuter/stations.
      # Handles the GeoJSON coordinate order swap ([lng, lat] → lat/lng fields).
      def self.from_hash(h)
        # Upstream GeoJSON: coordinates[0] = longitude, coordinates[1] = latitude.
        # We extract them into clearly named variables to make the swap visible.
        lng, lat = h["geometry"]["coordinates"]

        new(
          id:        SLUG_BY_UPSTREAM_ID.fetch(h["id"]),
          name:      h["name"],
          latitude:  lat,
          longitude: lng,
          modes:     h["modes"].map(&:downcase)  # "Rail" → "rail"
        )
      end

      # ── Predicate helpers ─────────────────────────────────────────────────

      def rail?
        modes.include?("rail")
      end

      def bus?
        modes.include?("bus")
      end

      # ── Serialisation ─────────────────────────────────────────────────────

      # Returns a plain hash suitable for JSON serialisation.
      # We override Struct's default to_h so we control key order and
      # exclude any internal fields we don't want in the API response.
      def to_h
        {
          id:        id,
          name:      name,
          latitude:  latitude,
          longitude: longitude,
          modes:     modes
        }
      end
    end
  end
end