require 'rack/test'
require 'json'
require_relative 'api' # This requires sinatra and mounts the routes

class PaginationTester
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def run_test
    # Setup initial request for the beginning of the day.
    # 05:00 SAST = 03:00 UTC
    target_date = "2026-06-17T05:00:00+02:00"
    
    puts "Starting pagination test at #{target_date}..."
    response = get "/v1/journeys?from=sandton&to=hatfield&requested_time=#{target_date}"
    
    json = JSON.parse(response.body)
    journeys = json["journeys"] || []
    cursor = json.dig("meta", "next_cursor")
    
    all_trains = journeys.dup
    page = 1
    
    if journeys.any?
      puts "Page #{page}: found #{journeys.size} trains. Last train departs at: #{journeys.last['departure_time']}. Cursor: #{cursor}"
    end
    
    while cursor
      page += 1
      response = get "/v1/journeys?from=sandton&to=hatfield&next_cursor=#{cursor}"
      json = JSON.parse(response.body)
      
      journeys = json["journeys"] || []
      cursor = json.dig("meta", "next_cursor")
      
      all_trains.concat(journeys)
      
      if journeys.any?
        puts "Page #{page}: found #{journeys.size} trains. Last train departs at: #{journeys.last['departure_time']}. Cursor: #{cursor}"
      else
        puts "Page #{page}: found 0 trains. Pagination complete. Cursor: #{cursor}"
      end
      
      if page > 50
        puts "ERROR: Infinite loop detected!"
        break
      end
    end
    
    puts "\nTotal unique trains found for the day: #{all_trains.map{|t| t['departure_time']}.uniq.size}"
    if all_trains.any?
      puts "First train: #{all_trains.first['departure_time']}"
      puts "Last train: #{all_trains.last['departure_time']}"
    end
  end
end

PaginationTester.new.run_test
