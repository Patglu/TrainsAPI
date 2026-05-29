# frozen_string_literal: true

require "dotenv/load"
require "set"

# 1. Add 'lib' to the load path so Ruby can find your models
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

# 2. Pre-load your models so they are available globally
require "gautrain_client/models/concerns/time_parsing"
require "gautrain_client/models/station"
require "gautrain_client/models/leg"
require "gautrain_client/models/itinerary"

# 3. Load the app
require_relative "api/server"

# Serve static files from the /public directory
use Rack::Static, urls: ["/api_docs.html"], root: "public"

# Rack::Cors allows mobile apps (different origins) to access the API
require "rack/cors"
use Rack::Cors do
  allow do
    origins "*"
    resource "*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options]
  end
end

run TrainTimesAPI::Server