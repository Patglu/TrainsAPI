require 'net/http'
require 'json'
require 'time'

# Arrive by 10:45 SAST
arrive_by_sast = Time.parse("2026-06-24T10:45:00+02:00")
start_time = arrive_by_sast - (180 * 60) # 3 hours

uri = URI("https://www.gautrain.co.za/commuter/route")
uri.query = URI.encode_www_form(
  orgLng: 28.05693,
  orgLat: -26.10858,
  dstLng: 28.04451,
  dstLat: -26.14622,
  publicOperators: "",
  isParking: false,
  earliestArrival: start_time.iso8601,
  maxItineraries: 10,
  isGeometryReturned: false,
  isImmutable: false
)

req = Net::HTTP::Get.new(uri)
req['Accept'] = 'application/json'
res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

json = JSON.parse(res.body)
itineraries = json["itineraries"]

puts "Fetched #{itineraries.size} itineraries:"
