# frozen_string_literal: true

# This file is loaded by api/server.rb and runs inside the TrainTimesAPI::Server class.
require "digest"

get "/v1/stations" do
  # 1. Set dynamic Cache-Control headers for the static station list (24 hours).
  #    Intermediary proxies, CDNs, and mobile client networking stacks (like URLSession or OkHttp)
  #    will cache this response directly on their end, skipping the trip to our server.
  headers["Cache-Control"] = "public, max-age=86400"

  # 2. Call our Gautrain client to get the station list.
  #    fetch_all returns the raw array of Station model objects,
  #    while caching it internally inside the Stations client's CacheStore.
  station_objects = STATIONS_CLIENT.fetch_all
  station_hashes  = station_objects.map(&:to_h)

  # 3. Evaluate ETag header validation on the serialized station array.
  #    If the client's If-None-Match matches this SHA-256 fingerprint, Sinatra will
  #    immediately halt with a 304 Not Modified status and drop the response body.
  etag Digest::SHA256.hexdigest(station_hashes.to_json)

  # 4. Retrieve cache metadata directly from the Stations client's CacheStore
  #    to calculate accurate telemetry parameters.
  cache_result = STATIONS_CLIENT.instance_variable_get(:@cache).read("stations")

  if cache_result
    cached_at   = cache_result.cached_at
    status      = cache_result.status
    age_seconds = (Time.now - cached_at).round
    ttl_seconds = cache_result.ttl_seconds
  else
    # Fallback in the rare event of a cold-boot miss race condition
    cached_at   = Time.now
    status      = "miss"
    age_seconds = 0
    ttl_seconds = 86_400
  end

  # 5. Build the meta object. We use the cache record's creation timestamp (cached_at)
  #    as the semantic "as_of" marker rather than generating a fake real-time timestamp.
  response_meta = {
    count: station_hashes.length,
    as_of: cached_at.utc.iso8601,
    cache: {
      status:      status,
      cached_at:   cached_at.utc.iso8601,
      age_seconds: age_seconds,
      ttl_seconds: ttl_seconds
    }
  }

  # 6. Use the send_success helper to write the JSON payload.
  send_success(
    { stations: station_hashes },
    response_meta
  )
end
