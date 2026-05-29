# frozen_string_literal: true

module GautrainClient
  # TTLResolver decides how long to cache journey data based on the
  # current time in SAST (UTC+2), aligned with Gautrain's published
  # peak hours. All methods are class-level — no state needed.
  module TTLResolver
    # Seconds offset from UTC to SAST (South Africa Standard Time).
    # SAST is UTC+2 and has no daylight saving — the offset never changes.
    SAST_OFFSET = 2 * 3600

    PEAK_MORNING_START =  6.0# 06:00 SAST
    PEAK_MORNING_END   =  9.0# 09:00 SAST
    PEAK_AFTERNOON_START = 15.0# 15:00 SAST
    PEAK_AFTERNOON_END   = 18.5# 18:30 SAST (0.5 = 30 minutes)

    TTL_PEAK    = 15# seconds — tight window, trains every 10 min
    TTL_OFFPEAK = 60# seconds — trains every 20 min
    TTL_WEEKEND = 120# seconds — reduced weekend schedule

    # Returns the appropriate TTL in seconds for the current moment.
    # `now` defaults to Time.now but can be injected in tests so we
    # can simulate any time of day without sleeping or mocking Time.
    def self.for_journeys(now = Time.now)
      sast = now.utc + SAST_OFFSET

      # Weekend? (wday: 0 = Sunday, 6 = Saturday)
      return TTL_WEEKEND if sast.wday == 0 || sast.wday == 6

      # Convert hour + minutes to a decimal for easy range comparison.
      # e.g. 08:45 → 8.75, 18:30 → 18.5
      hour = sast.hour + sast.min / 60.0

      # Is it morning or afternoon peak?
      # Range#cover? is slightly faster than Range#include? for floats.
      if (PEAK_MORNING_START...PEAK_MORNING_END).cover?(hour) ||
         (PEAK_AFTERNOON_START...PEAK_AFTERNOON_END).cover?(hour)
        TTL_PEAK
      else
        TTL_OFFPEAK
      end
    end

    # Convenience — call peak? from anywhere to know the current window.
    def self.peak?(now = Time.now)
      for_journeys(now) == TTL_PEAK
    end
  end
end