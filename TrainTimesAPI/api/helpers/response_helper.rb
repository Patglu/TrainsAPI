# frozen_string_literal: true

module Helpers
  module ResponseHelper
    private

    def send_success(data, meta = {}, status = 200)
      halt status, { "Content-Type" => "application/json" },
           JSON.generate({ data: data, meta: meta })
    end

    # RFC 7807 Standardized error output
    def send_error(code, message, details = {}, status = 400)
      req_id = Thread.current[:request_id] || "unknown"
      payload = {
        type:     "https://traintimes.api/errors/#{code}",
        title:    code.to_s.gsub("_", " ").capitalize,
        status:   status,
        detail:   message,
        instance: "/v1/errors/#{req_id}"
      }.merge(details)

      halt status, { "Content-Type" => "application/problem+json" },
           JSON.generate(payload)
    end
  end
end