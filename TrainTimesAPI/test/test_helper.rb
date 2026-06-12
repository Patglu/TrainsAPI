# frozen_string_literal: true

ENV["RACK_ENV"] = "test"
ENV["API_KEY"] ||= "test-api-key"

require "dotenv/load"
require "minitest/autorun"
require "rack/test"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gautrain_client/models/concerns/time_parsing"
require "gautrain_client/models/station"
require "gautrain_client/models/leg"
require "gautrain_client/models/itinerary"
require_relative "../api/server"

class Minitest::Test
  include Rack::Test::Methods

  def app
    TrainTimesAPI::Server
  end
end
