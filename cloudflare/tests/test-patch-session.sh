#!/bin/bash

# Test PATCH endpoint for session updates
# Usage: ./test-patch-session.sh

set -e

# Configuration
BASE_URL="${ERA_URL:-http://localhost:8787}"
SESSION_ID="test-patch-$(date +%s)"

echo "=== Testing Session PATCH Endpoint ==="
echo "Base URL: $BASE_URL"
echo "Session ID: $SESSION_ID"
echo

# 1. Create a test session with default timeout
echo "1. Creating test session with default_timeout=30..."
CREATE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "session_id": "'"$SESSION_ID"'",
    "persistent": true,
    "default_timeout": 30
  }')

CREATED_TIMEOUT=$(echo "$CREATE_RESPONSE" | jq -r '.default_timeout')
echo "   Created session with default_timeout: $CREATED_TIMEOUT"
echo

# 2. Update session default_timeout to 120
echo "2. Updating default_timeout to 120..."
UPDATE_RESPONSE=$(curl -s -X PATCH "$BASE_URL/api/sessions/$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "default_timeout": 120
  }')

UPDATED_TIMEOUT=$(echo "$UPDATE_RESPONSE" | jq -r '.metadata.default_timeout')
echo "   Updated default_timeout: $UPDATED_TIMEOUT"
echo

# 3. Verify the update persisted by fetching session
echo "3. Verifying update persisted..."
GET_RESPONSE=$(curl -s -X GET "$BASE_URL/api/sessions/$SESSION_ID")
CURRENT_TIMEOUT=$(echo "$GET_RESPONSE" | jq -r '.default_timeout')
echo "   Current default_timeout: $CURRENT_TIMEOUT"
echo

# 4. Test invalid timeout (negative number)
echo "4. Testing invalid timeout (should fail)..."
INVALID_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH "$BASE_URL/api/sessions/$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "default_timeout": -1
  }')

STATUS=$(echo "$INVALID_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
if [ "$STATUS" = "400" ]; then
  echo "   ✅ Correctly rejected invalid timeout (HTTP 400)"
else
  echo "   ❌ Expected HTTP 400 but got: $STATUS"
fi
echo

# 5. Test updating allowInternetAccess
echo "5. Updating allowInternetAccess to false..."
UPDATE_ACCESS=$(curl -s -X PATCH "$BASE_URL/api/sessions/$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "allowInternetAccess": false
  }')

ACCESS_VALUE=$(echo "$UPDATE_ACCESS" | jq -r '.metadata.allowInternetAccess')
echo "   Updated allowInternetAccess: $ACCESS_VALUE"
echo

# 6. Test code execution with updated timeout
echo "6. Testing code execution uses updated timeout..."
RUN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import os; print(f\"Session has default timeout\")"
  }')

STDOUT=$(echo "$RUN_RESPONSE" | jq -r '.stdout')
EXIT_CODE=$(echo "$RUN_RESPONSE" | jq -r '.exit_code')
echo "   Exit code: $EXIT_CODE"
echo "   Output: $STDOUT"
echo

# 7. Clean up
echo "7. Cleaning up..."
curl -s -X DELETE "$BASE_URL/api/sessions/$SESSION_ID" > /dev/null
echo "   ✅ Test session deleted"
echo

# Results
echo "=== Test Results ==="
if [ "$UPDATED_TIMEOUT" = "120" ] && [ "$CURRENT_TIMEOUT" = "120" ] && [ "$STATUS" = "400" ] && [ "$ACCESS_VALUE" = "false" ]; then
  echo "✅ All tests passed!"
  echo "   - Session default_timeout updated successfully (30 → 120)"
  echo "   - Update persisted correctly"
  echo "   - Invalid values rejected appropriately"
  echo "   - allowInternetAccess updated successfully"
  exit 0
else
  echo "❌ Some tests failed"
  echo "   UPDATED_TIMEOUT: $UPDATED_TIMEOUT (expected: 120)"
  echo "   CURRENT_TIMEOUT: $CURRENT_TIMEOUT (expected: 120)"
  echo "   STATUS: $STATUS (expected: 400)"
  echo "   ACCESS_VALUE: $ACCESS_VALUE (expected: false)"
  exit 1
fi
