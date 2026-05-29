# frozen_string_literal: true
require "faraday"
require "json"

module GautrainClient
  class HttpClient
    BASE_URL        = "https://www.gautrain.co.za"
    # How long to wait for a TCP connection.
    CONNECT_TIMEOUT = 5
    # How long to wait for the response body after connecting.
    READ_TIMEOUT    = 10

    def initialize
      @conn = Faraday.new(url: BASE_URL) do |f|
        f.headers["Accept"]           = "application/json, text/javascript, */*; q=0.01"
        f.headers["X-Requested-With"] = "XMLHttpRequest"
        f.headers["Referer"]          = "https://www.gautrain.co.za/"
        f.headers["Pragma"]           = "no-cache"
        f.headers["Cache-Control"]    = "no-cache"
        f.request :url_encoded
        f.options.timeout      = READ_TIMEOUT
        f.options.open_timeout = CONNECT_TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    def get(path, params = {})
      response = @conn.get(path, params)

      # Faraday does NOT raise on 4xx/5xx — it returns a normal response object.
      unless response.success?
        raise Error, "Upstream returned HTTP #{response.status} for #{path}"
      end

      begin
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "Upstream returned non-JSON body: #{e.message[0, 80]}"
      end

    rescue Faraday::TimeoutError => e
      raise Error, "Upstream timed out: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      raise Error, "Cannot reach upstream: #{e.message}"
    rescue Faraday::Error => e
      raise Error, "Upstream request failed: #{e.message}"
    end
  end

  # GautrainClient::Error is our domain error — one class for all upstream failures.
  class Error < StandardError; end
end
