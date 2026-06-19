require 'time'
t = Time.parse("2026-06-24T10:45:00Z").getlocal("+02:00")
puts t.iso8601
puts t.strftime("%Y-%m-%dT%H:%M:%S")

t2 = Time.parse("2026-06-24T10:45:00+02:00")
puts t2.strftime("%Y-%m-%dT%H:%M:%S")
