#!/bin/bash

# Test PATCH endpoint for VM updates
# Usage: ./test-patch.sh

set -e

AGENT_URL="http://localhost:8787"

echo "=== Testing VM PATCH Endpoint ==="
echo

# 1. Start agent in background (skip if already running)
echo "1. Starting era-agent..."
AGENT_MODE=http timeout 30 ./agent &
AGENT_PID=$!
sleep 3

# 2. Create a test VM
echo "2. Creating test VM..."
VM_RESPONSE=$(curl -s -X POST "$AGENT_URL/api/vm" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "cpu_count": 1,
    "memory_mib": 256,
    "network_mode": "none",
    "persist": false
  }')

VM_ID=$(echo "$VM_RESPONSE" | jq -r '.id')
echo "   VM ID: $VM_ID"
echo "   Initial network_mode: $(echo "$VM_RESPONSE" | jq -r '.network_mode')"
echo

# 3. Update VM network_mode from 'none' to 'host'
echo "3. Updating VM network_mode to 'host'..."
UPDATE_RESPONSE=$(curl -s -X PATCH "$AGENT_URL/api/vm/$VM_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "network_mode": "host"
  }')

UPDATED_MODE=$(echo "$UPDATE_RESPONSE" | jq -r '.network_mode')
echo "   Updated network_mode: $UPDATED_MODE"
echo

# 4. Verify the update persisted
echo "4. Verifying update persisted..."
GET_RESPONSE=$(curl -s -X GET "$AGENT_URL/api/vm/$VM_ID")
CURRENT_MODE=$(echo "$GET_RESPONSE" | jq -r '.network_mode')
echo "   Current network_mode: $CURRENT_MODE"
echo

# 5. Test invalid network_mode
echo "5. Testing invalid network_mode (should fail)..."
INVALID_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH "$AGENT_URL/api/vm/$VM_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "network_mode": "invalid"
  }')

STATUS=$(echo "$INVALID_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
if [ "$STATUS" = "400" ]; then
  echo "   ✅ Correctly rejected invalid network_mode (HTTP 400)"
else
  echo "   ❌ Expected HTTP 400 but got: $STATUS"
fi
echo

# 6. Clean up
echo "6. Cleaning up..."
curl -s -X DELETE "$AGENT_URL/api/vm/$VM_ID" > /dev/null
kill $AGENT_PID 2>/dev/null || true
echo "   ✅ Test VM deleted"
echo

# Results
echo "=== Test Results ==="
if [ "$UPDATED_MODE" = "host" ] && [ "$CURRENT_MODE" = "host" ] && [ "$STATUS" = "400" ]; then
  echo "✅ All tests passed!"
  echo "   - VM network_mode updated successfully"
  echo "   - Update persisted correctly"
  echo "   - Invalid values rejected appropriately"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi
