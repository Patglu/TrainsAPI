require 'time'
require 'date'

after_param = "2026-06-17T22:00:00Z"
target_date = Time.parse(after_param).getlocal("+02:00").to_date
puts "Target date: #{target_date}"

train1 = "2026-06-17T22:30:00Z"
train2 = "2026-06-18T04:17:00Z"

puts "Train 1 date: #{Time.parse(train1).getlocal("+02:00").to_date}"
puts "Train 1 keep: #{Time.parse(train1).getlocal("+02:00").to_date == target_date}"

puts "Train 2 date: #{Time.parse(train2).getlocal("+02:00").to_date}"
puts "Train 2 keep: #{Time.parse(train2).getlocal("+02:00").to_date == target_date}"
