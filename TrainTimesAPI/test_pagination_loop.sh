#!/bin/bash
# Start the server
bundle exec rackup -p 9293 &
SERVER_PID=$!
sleep 3 # Wait for server to boot

echo "Starting infinite pagination test at 05:00 SAST on 2026-06-17..."
# Initial request
RESPONSE=$(curl -s -H "X-Api-Key: change-me-to-something-strong" "http://localhost:9293/v1/journeys?from=sandton&to=hatfield&requested_time=2026-06-17T05:00:00Z")

COUNT=$(echo "$RESPONSE" | jq -r '.meta.count')
CURSOR=$(echo "$RESPONSE" | jq -r '.meta.next_cursor')

if [ "$COUNT" -gt 0 ]; then
  LAST_TRAIN=$(echo "$RESPONSE" | jq -r '.journeys[-1].departure_time')
  echo "Page 1: found $COUNT trains. Last train departs at: $LAST_TRAIN. Cursor: $CURSOR"
else
  echo "Page 1: found 0 trains."
fi

PAGE=1
TOTAL_TRAINS=$COUNT

while [ "$CURSOR" != "null" ] && [ -n "$CURSOR" ]; do
  PAGE=$((PAGE + 1))
  RESPONSE=$(curl -s -H "X-Api-Key: change-me-to-something-strong" "http://localhost:9293/v1/journeys?from=sandton&to=hatfield&next_cursor=$CURSOR")
  
  COUNT=$(echo "$RESPONSE" | jq -r '.meta.count')
  CURSOR=$(echo "$RESPONSE" | jq -r '.meta.next_cursor')
  LAST_CALL=$(echo "$RESPONSE" | jq -r '.meta.last_call')
  LAST_TRAIN_LEFT=$(echo "$RESPONSE" | jq -r '.meta.last_train_has_left')
  
  if [ "$COUNT" -gt 0 ]; then
    LAST_TRAIN=$(echo "$RESPONSE" | jq -r '.journeys[-1].departure_time')
    echo "Page $PAGE: found $COUNT trains. Last departs at: $LAST_TRAIN. last_call: $LAST_CALL, last_train_has_left: $LAST_TRAIN_LEFT"
    TOTAL_TRAINS=$((TOTAL_TRAINS + COUNT))
    
    # Check if we've reached June 19th (the day after tomorrow)
    if [[ "$LAST_TRAIN" == 2026-06-19* ]]; then
      echo "Reached day after tomorrow (June 19th). Stopping test."
      break
    fi
  else
    echo "Page $PAGE: found 0 trains. Pagination complete. Cursor: $CURSOR"
  fi
  
  if [ $PAGE -gt 50 ]; then
    echo "ERROR: Infinite loop reached 50 pages!"
    break
  fi
done

echo ""
echo "Total trains found for today and tomorrow: $TOTAL_TRAINS"

# Kill the server
kill $SERVER_PID
