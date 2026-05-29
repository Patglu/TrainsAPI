# frozen_string_literal: true

require "time"

module GautrainClient
  module Models
    # TimeParsing is a small shared module that provides a single
    # `parse_time` helper for every model that needs to convert
    # upstream ISO 8601 strings into UTC ISO 8601 strings.
    #
    # Without this, `parse_time` was defined twice — identically —
    # in both Leg and Itinerary. Any future change (e.g. adding
    # timezone handling) would have to be made in two places.
    #
    # USAGE: extend TimeParsing inside a class or module to make
    # `parse_time` available as a class-level method.
    #
    #   class Leg
    #     extend TimeParsing
    #     def self.from_hash(h)
    #       departure_time = parse_time(h["departureTime"])
    #     end
    #   end
    module TimeParsing
      # Converts an ISO 8601 string from Gautrain into a UTC ISO 8601 string.
      #
      # Time.parse   — parses the string into a Ruby Time object
      # .utc         — ensures the timezone is UTC (Gautrain sends "Z" suffix
      #                already, but .utc is idempotent and defensive)
      # .iso8601     — formats back to "2026-05-26T10:34:36Z"
      #
      # The rescue handles nil input or malformed strings without crashing —
      # returns nil so the caller can decide what to do with a missing timestamp.
      def parse_time(str)
        Time.parse(str).utc.iso8601
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end