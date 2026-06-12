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
  includes             = params["include"].to_s.split(",").map(&:strip)
  include_polylines    = includes.include?("polylines")
  include_intermediate = params["include_intermediate"] == "true" || includes.include?("intermediate_stations")
  requested_time       = params["requested_time"]&.strip
  requested_time       = nil if requested_time&.empty?

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
    requested_time:    requested_time,
    include_polylines: include_polylines
  )

  # Extract values from the wrapped cache payload
  journey_data   = result.value
  itineraries    = journey_data[:itineraries]
  journey_hashes = itineraries.map { |iti| iti.to_h(include_intermediate: include_intermediate) }

  # Evaluate ETag header validation on the serialized journey content payload
  # Bypassed when given a cursor to guarantee perfect continuity.
  etag Digest::SHA256.hexdigest(journey_hashes.to_json) unless after_param

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

  # Check if the journey involves crossing rail lines (transfer required)
  crosses_lines = itineraries.any? do |iti|
    rail_legs = iti.legs.select { |leg| leg.mode == "rail" }
    rail_legs.size > 1 && rail_legs.map(&:line_name).uniq.size > 1
  end

  meta[:transfer_required] = crosses_lines

  # Calculate reference time and date in SAST timezone (UTC+2)
  ref_time = requested_time ? Time.parse(requested_time) : @request_start
  ref_date_sast = ref_time.getlocal("+02:00").to_date

  if itineraries.any?
    first_dep_date_sast = Time.parse(itineraries.first.departure_time).getlocal("+02:00").to_date
    last_train_has_left = first_dep_date_sast > ref_date_sast

    last_call = if first_dep_date_sast == ref_date_sast
                  if itineraries.size == 1
                    true
                  else
                    second_dep_date_sast = Time.parse(itineraries[1].departure_time).getlocal("+02:00").to_date
                    second_dep_date_sast > ref_date_sast
                  end
                else
                  false
                end
  else
    last_train_has_left = true
    last_call = false
  end

  meta[:last_train_has_left] = last_train_has_left
  meta[:last_call]           = last_call

  send_success({ journeys: journey_hashes }, meta)
end
