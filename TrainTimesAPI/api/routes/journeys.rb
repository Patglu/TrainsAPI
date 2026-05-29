# frozen_string_literal: true

require "base64"
require "digest"

get "/v1/journeys" do
  from_slug = params["from"]&.strip&.downcase
  to_slug   = params["to"]&.strip&.downcase

  # 1. Presence — both params must exist and be non-empty.
  if from_slug.nil? || from_slug.empty?
    send_error("missing_parameter", "Parameter 'from' is required", { parameter: "from" })
  end
  if to_slug.nil? || to_slug.empty?
    send_error("missing_parameter", "Parameter 'to' is required", { parameter: "to" })
  end

  # 2. Known slug — both must be in our station set (O(1) lookup via Set).
  unless GautrainClient::Models::Station::VALID_SLUGS.include?(from_slug)
    send_error("unknown_station", "Unknown station: '#{from_slug}'",
               { parameter: "from", value: from_slug,
                 valid_stations: GautrainClient::Models::Station::VALID_SLUGS.to_a.sort })
  end
  unless GautrainClient::Models::Station::VALID_SLUGS.include?(to_slug)
    send_error("unknown_station", "Unknown station: '#{to_slug}'",
               { parameter: "to", value: to_slug,
                 valid_stations: GautrainClient::Models::Station::VALID_SLUGS.to_a.sort })
  end

  # 3. Same-station — origin and destination must differ.
  if from_slug == to_slug
    send_error("same_station", "Origin and destination must be different stations",
               { from: from_slug, to: to_slug })
  end

  # 4. Decoupled Pagination — parse Base64 cursor if present.
  after_param = params["after"]&.strip
  if after_param&.empty?
    after_param = nil
  elsif after_param
    begin
      decoded_cursor = Base64.urlsafe_decode64(after_param)
      Time.parse(decoded_cursor) # Verify it is a valid date
      after_param = decoded_cursor
    rescue ArgumentError, TypeError
      send_error("invalid_cursor", "The pagination cursor supplied is malformed or invalid.", {}, 400)
    end
  end

  # All validation passed. Build the includes list and call the client.
  includes        = params["include"].to_s.split(",").map(&:strip)
  include_polylines = includes.include?("polylines")

  # First-page requests can be cached briefly, but cursor pagination must stay live.
  if after_param
    headers["Cache-Control"] = "no-store"
  else
    ttl = GautrainClient::TTLResolver.for_journeys
    headers["Cache-Control"] = "public, max-age=#{ttl}"
  end

  # Fetch now returns a CacheStore::Result wrapping our journey data payload
  result       = JOURNEYS_CLIENT.fetch(
    origin_slug:       from_slug,
    destination_slug:  to_slug,
    after_timestamp:   after_param,
    include_polylines: include_polylines
  )

  # Extract values from the wrapped cache payload
  journey_data   = result.value
  itineraries    = journey_data[:itineraries]
  journey_hashes = itineraries.map(&:to_h)

  # Evaluate ETag header validation on the serialized journey content payload
  etag Digest::SHA256.hexdigest(journey_hashes.to_json)

  # Calculate the in-memory age of the returned cache record
  age_seconds = (Time.now - result.cached_at).round

  # Server-side Base64 cursor encoding
  raw_cursor = itineraries.last&.departure_time
  opaque_cursor = raw_cursor ? Base64.urlsafe_encode64(raw_cursor, padding: false) : nil

  meta = {
    count:       journey_hashes.length,
    from:        from_slug,
    to:          to_slug,
    next_cursor: opaque_cursor,
    as_of:       journey_data[:as_of],
    cache: {
      status:      result.status,
      cached_at:   result.cached_at.utc.iso8601,
      age_seconds: age_seconds,
      ttl_seconds: result.ttl_seconds
    }
  }

  # includes only appears in meta when the request actually used ?include=
  meta[:includes] = includes unless includes.empty?

  send_success({ journeys: journey_hashes }, meta)
end
