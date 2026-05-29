# frozen_string_literal: true

require "json"
require "logger"

module Helpers
  module LoggingHelper
    # One shared Logger instance for the whole app, writing to stdout.
    # Cloud platforms (Fly.io, Heroku, Render) capture stdout automatically —
    # no file path or rotation configuration needed.
    LOGGER = Logger.new($stdout)
    LOGGER.formatter = proc do |_severity, _datetime, _progname, msg|
      # Logger adds its own timestamp prefix by default. We suppress it
      # because our log entries already carry a "timestamp" field in JSON.
      "#{msg}\n"
    end

    private

    # Public interface — call these from routes and error handlers.
    # Each method accepts a hash of key-value pairs to merge into the log line.
    def log_info(data = {});  log("INFO",  data); end
    def log_warn(data = {});  log("WARN",  data); end
    def log_error(data = {}); log("ERROR", data); end

    def log(level, data)
      # Build the base entry with the three fields every line must have,
      # then merge in whatever the caller provided.
      # `.merge` means caller-supplied keys override base keys on collision —
      # unlikely, but handled gracefully rather than raising an error.
      entry = {
        level:      level,
        timestamp:  Time.now.utc.iso8601,
        # Thread.current[:request_id] is set in server.rb's before filter.
        # Thread-local storage keeps it isolated per concurrent request —
        # a plain instance variable would be shared across threads.
        request_id: Thread.current[:request_id]
      }.merge(data)
      LOGGER.info(entry.to_json)
    end
  end
end