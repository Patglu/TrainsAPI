# frozen_string_literal: true

require_relative "test_helper"

class JourneysTest < Minitest::Test
  def setup
    header "X-API-KEY", "test-api-key"
  end

  # Helper to construct a mock itinerary
  def build_mock_itinerary(id, departure_time_utc, legs: [])
    GautrainClient::Models::Itinerary.new(
      id: id,
      departure_time: departure_time_utc,
      arrival_time: departure_time_utc, # simple mock
      duration_seconds: 1800,
      legs: legs,
      parking_cost_zar: 25.0
    )
  end

  def build_mock_leg(id, mode, line_name)
    GautrainClient::Models::Leg.new(
      id: id,
      mode: mode,
      line_name: line_name,
      line_colour: "#000",
      departure_stop: "stop_a",
      arrival_stop: "stop_b",
      departure_time: "2026-06-12T10:00:00Z",
      arrival_time: "2026-06-12T10:10:00Z",
      duration_seconds: 600,
      distance_metres: 5000,
      headsign: "headsign",
      carriages: 4,
      fare_amount_zar: 20.0,
      fare_is_peak: false,
      fare_product: "Pay-As-You-Go",
      trip_id: "trip-1",
      waypoints: []
    )
  end

  def stub_journeys(itineraries)
    result = GautrainClient::CacheStore::Result.new(
      value: { itineraries: itineraries, as_of: "2026-06-12T10:00:00Z" },
      status: "fresh",
      cached_at: Time.now,
      ttl_seconds: 60
    )
    TrainTimesAPI::Server::JOURNEYS_CLIENT.stub(:fetch, result) do
      yield
    end
  end

  # Test Case 1: Normal Daytime Commute (neither last train nor last call)
  def test_normal_daytime_commute
    # Reference time: 12:00 SAST (10:00 UTC) on June 12
    # Itinerary 1: 12:18 SAST (10:18 UTC)
    # Itinerary 2: 12:38 SAST (10:38 UTC)
    iti1 = build_mock_itinerary("iti-1", "2026-06-12T10:18:48Z")
    iti2 = build_mock_itinerary("iti-2", "2026-06-12T10:38:48Z")

    stub_journeys([iti1, iti2]) do
      get "/v1/journeys?from=sandton&to=hatfield&requested_time=2026-06-12T12:00:00%2B02:00"
      
      assert_equal 200, last_response.status
      json = JSON.parse(last_response.body)
      
      assert_equal false, json.dig("meta", "last_train_has_left")
      assert_equal false, json.dig("meta", "last_call")
    end
  end

  # Test Case 2: Last Call (only 1 train left today)
  def test_last_call
    # Reference time: 20:20 SAST (18:20 UTC) on June 12
    # Itinerary 1: 20:38 SAST (18:38 UTC) -> departs today
    # Itinerary 2: 05:38 SAST (03:38 UTC) next day -> departs tomorrow
    iti1 = build_mock_itinerary("iti-1", "2026-06-12T18:38:48Z")
    iti2 = build_mock_itinerary("iti-2", "2026-06-13T03:38:48Z")

    stub_journeys([iti1, iti2]) do
      get "/v1/journeys?from=sandton&to=hatfield&requested_time=2026-06-12T20:20:00%2B02:00"
      
      assert_equal 200, last_response.status
      json = JSON.parse(last_response.body)
      
      assert_equal false, json.dig("meta", "last_train_has_left")
      assert_equal true, json.dig("meta", "last_call")
    end
  end

  # Test Case 3: Last Train Has Left (all remaining trains depart tomorrow or later)
  def test_last_train_has_left
    # Reference time: 21:30 SAST (19:30 UTC) on June 12
    # Itinerary 1: 05:38 SAST (03:38 UTC) next day -> departs tomorrow
    # Itinerary 2: 06:08 SAST (04:08 UTC) next day -> departs tomorrow
    iti1 = build_mock_itinerary("iti-1", "2026-06-13T03:38:48Z")
    iti2 = build_mock_itinerary("iti-2", "2026-06-13T04:08:48Z")

    stub_journeys([iti1, iti2]) do
      get "/v1/journeys?from=sandton&to=hatfield&requested_time=2026-06-12T21:30:00%2B02:00"
      
      assert_equal 200, last_response.status
      json = JSON.parse(last_response.body)
      
      assert_equal true, json.dig("meta", "last_train_has_left")
      assert_equal false, json.dig("meta", "last_call")
    end
  end

  # Test Case 4: Transfer Required
  def test_transfer_required
    # Itinerary with two rail legs on different lines
    leg1 = build_mock_leg("leg-1", "rail", "North - South Line")
    leg2 = build_mock_leg("leg-2", "rail", "East - West Line")
    iti = build_mock_itinerary("iti-cross", "2026-06-12T10:18:48Z", legs: [leg1, leg2])

    stub_journeys([iti]) do
      get "/v1/journeys?from=sandton&to=hatfield"
      
      assert_equal 200, last_response.status
      json = JSON.parse(last_response.body)
      
      assert_equal true, json.dig("meta", "transfer_required")
    end
  end

  # Test Case 5: Transfer Not Required
  def test_transfer_not_required
    # Itinerary with one rail leg
    leg1 = build_mock_leg("leg-1", "rail", "North - South Line")
    iti = build_mock_itinerary("iti-single", "2026-06-12T10:18:48Z", legs: [leg1])

    stub_journeys([iti]) do
      get "/v1/journeys?from=sandton&to=hatfield"
      
      assert_equal 200, last_response.status
      json = JSON.parse(last_response.body)
      
      assert_equal false, json.dig("meta", "transfer_required")
    end
  end

  # Test Case 6: Pagination Cursor Generation
  def test_pagination_cursor
    iti1 = build_mock_itinerary("iti-1", "2026-06-12T10:18:48Z")
    # The cursor should be 1 second after this last itinerary's departure time
    
    stub_journeys([iti1]) do
      get "/v1/journeys?from=sandton&to=hatfield"
      
      assert_equal 200, last_response.status
      json = JSON.parse(last_response.body)
      
      raw_cursor = "2026-06-12T10:18:49Z"
      expected_opaque = Base64.urlsafe_encode64(raw_cursor, padding: false)
      assert_equal expected_opaque, json.dig("meta", "next_cursor")
    end
  end

  # Test Case 7: Arrive By Feature
  def test_arrive_by
    # The route calls fetch_arrive_by directly, so we stub that method
    result = GautrainClient::CacheStore::Result.new(
      value: { itineraries: [build_mock_itinerary("iti-1", "2026-06-12T10:00:00Z")], as_of: "2026-06-12T10:00:00Z" },
      status: "fresh",
      cached_at: Time.now,
      ttl_seconds: 60
    )
    TrainTimesAPI::Server::JOURNEYS_CLIENT.stub(:fetch_arrive_by, result) do
      get "/v1/journeys?from=sandton&to=hatfield&arrive_by=2026-06-12T12:00:00%2B02:00"
      
      assert_equal 200, last_response.status
      json = JSON.parse(last_response.body)
      
      assert_equal 1, json.dig("data", "journeys").size
      refute_nil json.dig("meta", "next_cursor") # Seamless forward scrolling support
    end
  end

  # Test Case 8: Intermediate Stations Nesting
  def test_intermediate_stations_nesting
    leg1 = build_mock_leg("leg-1", "rail", "North - South Line")
    # Add mock waypoints to leg1
    leg1.waypoints = [
      { "stop" => { "name" => "Sandton" }, "departureTime" => "2026-06-12T10:00:00Z", "arrivalTime" => "2026-06-12T10:00:00Z" },
      { "stop" => { "name" => "Marlboro" }, "departureTime" => "2026-06-12T10:05:00Z", "arrivalTime" => "2026-06-12T10:04:00Z" },
      { "stop" => { "name" => "Midrand" }, "departureTime" => "2026-06-12T10:10:00Z", "arrivalTime" => "2026-06-12T10:09:00Z" },
      { "stop" => { "name" => "Centurion" }, "departureTime" => "2026-06-12T10:15:00Z", "arrivalTime" => "2026-06-12T10:14:00Z" },
      { "stop" => { "name" => "Pretoria" }, "departureTime" => "2026-06-12T10:20:00Z", "arrivalTime" => "2026-06-12T10:19:00Z" },
      { "stop" => { "name" => "Hatfield" }, "departureTime" => "2026-06-12T10:25:00Z", "arrivalTime" => "2026-06-12T10:24:00Z" }
    ]
    iti1 = build_mock_itinerary("iti-1", "2026-06-12T10:00:00Z", legs: [leg1])

    stub_journeys([iti1]) do
      get "/v1/journeys?from=sandton&to=hatfield&include=intermediate_stations"
      
      assert_equal 200, last_response.status
      json = JSON.parse(last_response.body)
      
      journey = json.dig("data", "journeys").first
      
      # Assert that intermediate_stations is NOT on the journey root
      assert_nil journey["intermediate_stations"]
      
      # Assert that intermediate_stations IS on the leg
      leg = journey["legs"].first
      refute_nil leg["intermediate_stations"]
      
      # There should be 4 intermediate stations (Marlboro, Midrand, Centurion, Pretoria)
      assert_equal 4, leg["intermediate_stations"].size
      assert_equal "marlboro", leg["intermediate_stations"][0]["id"]
      assert_equal "pretoria", leg["intermediate_stations"][3]["id"]
    end
  end
end
