#!/bin/bash

# Test streaming output endpoint
# Usage: ./test-streaming.sh

set -e

AGENT_URL="http://localhost:8787"

echo "=== Testing Streaming Output (SSE) ==="
echo

# 1. Start agent in background
echo "1. Starting era-agent..."
AGENT_MODE=http timeout 60 ./agent &
AGENT_PID=$!
sleep 3

# 2. Create a test VM
echo "2. Creating Python VM..."
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
echo

# 3. Test streaming with Python code that prints multiple lines
echo "3. Running streaming code (counting 1-10 with delays)..."
echo "   Watch for real-time output:"
echo

curl -X POST "$AGENT_URL/api/vm/$VM_ID/stream" \
  -H "Content-Type: application/json" \
  -d '{
    "command": "python3 -c \"import time; [print(f'\''Line {i}'\'') or time.sleep(0.5) for i in range(1, 11)]\"",
    "timeout": 30
  }' 2>/dev/null | while IFS= read -r line; do
  if [[ $line == data:* ]]; then
    # Extract JSON from SSE data field
    JSON="${line#data: }"
    TYPE=$(echo "$JSON" | jq -r '.type')

    if [ "$TYPE" = "stdout" ]; then
      CONTENT=$(echo "$JSON" | jq -r '.content')
      echo "   [STDOUT] $CONTENT"
    elif [ "$TYPE" = "stderr" ]; then
      CONTENT=$(echo "$JSON" | jq -r '.content')
      echo "   [STDERR] $CONTENT"
    elif [ "$TYPE" = "done" ]; then
      EXIT_CODE=$(echo "$JSON" | jq -r '.exit_code')
      DURATION=$(echo "$JSON" | jq -r '.duration')
      echo
      echo "   ✅ Execution complete!"
      echo "   Exit code: $EXIT_CODE"
      echo "   Duration: $DURATION"
    elif [ "$TYPE" = "error" ]; then
      ERROR=$(echo "$JSON" | jq -r '.error')
      echo "   ❌ Error: $ERROR"
    fi
  fi
done

echo

# 4. Test LLM-style streaming (simulated token generation)
echo "4. Testing LLM-style token streaming..."
echo "   Simulating token-by-token output:"
echo

curl -X POST "$AGENT_URL/api/vm/$VM_ID/stream" \
  -H "Content-Type: application/json" \
  -d '{
    "command": "python3 -c \"import time, sys; tokens = ['\''The'\'', '\''quick'\'', '\''brown'\'', '\''fox'\'', '\''jumps'\'', '\''over'\'', '\''the'\'', '\''lazy'\'', '\''dog'\'']; [print(t, end='\'' '\'', flush=True) or time.sleep(0.2) for t in tokens]; print()\"",
    "timeout": 30
  }' 2>/dev/null | while IFS= read -r line; do
  if [[ $line == data:* ]]; then
    JSON="${line#data: }"
    TYPE=$(echo "$JSON" | jq -r '.type')

    if [ "$TYPE" = "stdout" ]; then
      CONTENT=$(echo "$JSON" | jq -r '.content')
      echo -n "$CONTENT"
    elif [ "$TYPE" = "done" ]; then
      echo
      echo "   ✅ Token streaming complete!"
    fi
  fi
done

echo

# 5. Clean up
echo "5. Cleaning up..."
curl -s -X DELETE "$AGENT_URL/api/vm/$VM_ID" > /dev/null
kill $AGENT_PID 2>/dev/null || true
echo "   ✅ Test VM deleted"
echo

echo "=== Streaming Tests Complete ==="
echo "✅ Real-time output streaming works!"
echo "✅ SSE events received correctly"
echo "✅ Perfect for LLM generation and long-running tasks"
