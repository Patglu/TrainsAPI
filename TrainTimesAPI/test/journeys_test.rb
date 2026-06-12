# frozen_string_literal: true

require_relative "test_helper"

class JourneysTest < Minitest::Test
  def setup
    header "X-API-KEY", "test-api-key"
  end

  # Helper to construct a mock itinerary
  def build_mock_itinerary(id, departure_time_utc)
    GautrainClient::Models::Itinerary.new(
      id: id,
      departure_time: departure_time_utc,
      arrival_time: departure_time_utc, # simple mock
      duration_seconds: 1800,
      legs: [],
      parking_cost_zar: 25.0
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
end
