#!/bin/bash
# Test bulk session deletion

API_URL="https://era-agent.yawnxyz.workers.dev"
TIMESTAMP=$(date +%s)

echo "🧪 Testing Bulk Session Delete"
echo "================================"
echo ""

# Create 3 test sessions
echo "Creating 3 test sessions..."
for i in 1 2 3; do
  curl -s -X POST "$API_URL/api/sessions" \
    -H "Content-Type: application/json" \
    -d "{
      \"language\": \"python\",
      \"session_id\": \"test-bulk-${TIMESTAMP}-${i}\",
      \"persistent\": true
    }" | jq -r '.id'
done

echo ""
echo "---"
echo ""

# List sessions to verify they exist
echo "Listing sessions (should see 3 sessions):"
session_count=$(curl -s "$API_URL/api/sessions" | jq -r '.count')
echo "Total sessions: $session_count"
curl -s "$API_URL/api/sessions" | jq -r '.sessions[].id' | grep "test-bulk-${TIMESTAMP}"

echo ""
echo "---"
echo ""

# Delete all sessions
echo "Deleting all sessions..."
result=$(curl -s -X DELETE "$API_URL/api/sessions")
echo "$result" | jq '.'

deleted_count=$(echo "$result" | jq -r '.deleted_count')

if [ "$deleted_count" -gt 0 ]; then
  echo "✅ Bulk delete PASSED - deleted $deleted_count sessions"
else
  echo "❌ Bulk delete FAILED - no sessions deleted"
  exit 1
fi

echo ""
echo "---"
echo ""

# Verify all sessions are gone
echo "Verifying all sessions deleted (should be 0):"
final_count=$(curl -s "$API_URL/api/sessions" | jq -r '.count')
echo "Total sessions: $final_count"

if [ "$final_count" -eq 0 ]; then
  echo "✅ Verification PASSED - all sessions deleted"
else
  echo "❌ Verification FAILED - still have $final_count sessions"
  exit 1
fi

echo ""
echo "================================"
echo "✨ All tests PASSED!"
