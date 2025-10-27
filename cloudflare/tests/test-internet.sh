#!/bin/bash
# Test if containers have internet access

API_URL="https://era-agent.yawnxyz.workers.dev"
TIMESTAMP=$(date +%s)
SESSION_ID="test-internet-${TIMESTAMP}"

echo "Testing Internet Access..."
echo ""

# Create session
curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d "{\"language\": \"python\", \"session_id\": \"$SESSION_ID\", \"persistent\": false}" > /dev/null

# Test outbound connectivity
echo "1. Testing Python socket connection:"
curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"code": "import socket\ntry:\n    socket.create_connection((\"1.1.1.1\", 80), timeout=2)\n    print(\"✅ Internet access: YES\")\nexcept Exception as e:\n    print(f\"❌ Internet access: NO - {e}\")"}' | jq -r '.stdout'

echo ""
echo "2. Testing DNS resolution:"
curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"code": "import socket\ntry:\n    socket.gethostbyname(\"google.com\")\n    print(\"✅ DNS works\")\nexcept Exception as e:\n    print(f\"❌ DNS failed: {e}\")"}' | jq -r '.stdout'
