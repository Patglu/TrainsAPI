# frozen_string_literal: true

require "sinatra/base"
require "sinatra/json"
require "securerandom"
require_relative "helpers/logging_helper"
require_relative "helpers/response_helper"
require_relative "../lib/gautrain_client/http_client"
require_relative "../lib/gautrain_client/stations"
require_relative "../lib/gautrain_client/journeys"

# 1. Load standard library dependencies
require "time"
require "monitor"

# 2. Load core caching and helper layers first (needed by clients & warmer)
require_relative "../lib/gautrain_client/cache_store"
require_relative "../lib/gautrain_client/ttl_resolver"
require_relative "../lib/gautrain_client/cache_warmer"

# 3. Load the domain clients (which depend on cache_store and ttl_resolver)
require_relative "../lib/gautrain_client/stations"
require_relative "../lib/gautrain_client/journeys"
require_relative "../lib/gautrain_client/rate_limiter"

module TrainTimesAPI
  class Server < Sinatra::Base
    helpers Helpers::LoggingHelper, Helpers::ResponseHelper

    # Shared client instances — created once at boot, reused across requests.
    # STATIONS_CLIENT has an in-memory cache, so /commuter/stations is only
    # called once per server boot.
    # JOURNEYS_CLIENT receives STATIONS_CLIENT so it can resolve slugs to
    # coordinates internally — routes never touch raw lat/lng values.
    HTTP_CLIENT     = GautrainClient::HttpClient.new
    STATIONS_CLIENT = GautrainClient::Stations.new(HTTP_CLIENT)
    JOURNEYS_CLIENT = GautrainClient::Journeys.new(HTTP_CLIENT, STATIONS_CLIENT)

    # Start the background cache warm-up immediately on boot.
    # warm! returns instantly — the work happens in a separate thread.
    GautrainClient::CacheWarmer.new(JOURNEYS_CLIENT, STATIONS_CLIENT).warm!


    # ── Request lifecycle ──────────────────────────────────────────────────

    before do
      # A new UUID for every request, stored in thread-local storage so
      # concurrent requests handled by different Puma threads can't mix IDs.
      Thread.current[:request_id] = SecureRandom.uuid
      @request_start = Time.now
      log_info(event: "request_start", method: request.request_method, path: request.path_info)
    end

    after do
      duration_ms = ((Time.now - @request_start) * 1000).round
      log_info(event: "request_complete", status: response.status, duration_ms: duration_ms, path: request.path_info)
    end

    # ── Authentication ─────────────────────────────────────────────────────

    before "/v1/*" do
      api_key  = request.env["HTTP_X_API_KEY"]
      expected = ENV["API_KEY"]
      # secure_compare does constant-time string comparison to prevent
      # timing attacks that could reveal the key one character at a time.
      unless Rack::Utils.secure_compare(api_key.to_s, expected.to_s)
        send_error("unauthorized", "Missing or incorrect API key", {}, 401)
      end

      # Rate limiting to 60 requests per minute per key
      rate = GautrainClient::RateLimiter.throttle!(api_key)
      headers["X-RateLimit-Limit"] = "60"
      headers["X-RateLimit-Remaining"] = rate[:remaining].to_s
      headers["X-RateLimit-Reset"] = rate[:reset].to_s

      unless rate[:allowed]
        headers["X-RateLimit-After"] = rate[:reset_in].to_s
        send_error(:too_many_requests, "Rate limit exceeded. Please slow down.", {}, 429)
      end
    end



    # ── Error handlers ─────────────────────────────────────────────────────

    error GautrainClient::Error do
      err = env["sinatra.error"]
      log_error(event: "upstream_error", message: err.message, path: request.path_info)
      send_error("upstream_unavailable", "The timetable service is temporarily unavailable. Please try again.", {}, 502)
    end

    error StandardError do
      err = env["sinatra.error"]
      log_error(event: "internal_error", message: err.message, exception: err.class.name, path: request.path_info)
      send_error("internal_error", "An unexpected error occurred.", {}, 500)
    end

    # ── Health check ───────────────────────────────────────────────────────

    get "/health" do
      send_success({ status: "ok" }, { as_of: Time.now.utc.iso8601 })
    end

    # ── Load routes ────────────────────────────────────────────────────────

    Dir.glob(File.join(__dir__, "routes", "*.rb")).each do |file|
      class_eval File.read(file), file
    end
  end
end