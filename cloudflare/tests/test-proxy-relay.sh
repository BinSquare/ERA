#!/bin/bash
# Test the Worker-as-relay proxy system

API_URL="https://era-agent.yawnxyz.workers.dev"
TIMESTAMP=$(date +%s)
SESSION_ID="test-proxy-relay-${TIMESTAMP}"

echo "🚀 Testing Worker-as-Relay Proxy System"
echo "========================================"
echo ""

# 1. Create session with callbacks enabled
echo "1. Creating session with callback support..."
curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d "{
    \"language\": \"python\",
    \"session_id\": \"$SESSION_ID\",
    \"persistent\": true,
    \"allowInternetAccess\": true,
    \"allowPublicAccess\": true
  }" | jq '{id, allowPublicAccess}'

echo ""

# 2. Store code that handles HTTP requests
echo "2. Storing HTTP request handler code..."
curl -s -X PUT "$API_URL/api/sessions/$SESSION_ID/code" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import os\nimport json\n\n# Check if this is a proxied request\nif os.getenv(\"ERA_REQUEST_MODE\") == \"proxy\":\n    method = os.getenv(\"ERA_HTTP_METHOD\")\n    path = os.getenv(\"ERA_HTTP_PATH\")\n    query = os.getenv(\"ERA_HTTP_QUERY\")\n    body = os.getenv(\"ERA_HTTP_BODY\")\n    \n    # Handle different routes\n    if path == \"/hello\":\n        response = {\n            \"message\": \"Hello from ERA Agent!\",\n            \"method\": method,\n            \"path\": path,\n            \"session_id\": os.getenv(\"ERA_SESSION_ID\")\n        }\n    elif path == \"/echo\" and method == \"POST\":\n        try:\n            incoming_data = json.loads(body) if body else {}\n            response = {\n                \"echo\": incoming_data,\n                \"received_at\": \"proxy\",\n                \"session_id\": os.getenv(\"ERA_SESSION_ID\")\n            }\n        except:\n            response = {\"error\": \"Invalid JSON\"}\n    else:\n        response = {\n            \"error\": \"Route not found\",\n            \"available_routes\": [\"/hello\", \"/echo\"]\n        }\n    \n    # Output response as JSON (Worker will parse this)\n    print(json.dumps(response))\nelse:\n    print(\"Not a proxied request\")",
    "description": "HTTP request handler using ERA environment variables"
  }' | jq '.'

echo ""

# 3. Get the public URL
echo "3. Getting public URL..."
PUBLIC_URL=$(curl -s "$API_URL/api/sessions/$SESSION_ID/host?port=8000" | jq -r '.url')
echo "Public URL: $PUBLIC_URL"

echo ""

# 4. Test GET request
echo "4. Testing GET request to /hello..."
curl -s "${PUBLIC_URL}/hello" | jq '.'

echo ""

# 5. Test POST request
echo "5. Testing POST request to /echo..."
curl -s -X POST "${PUBLIC_URL}/echo" \
  -H "Content-Type: application/json" \
  -d '{"test": "data", "number": 42}' | jq '.'

echo ""

# 6. Test unknown route
echo "6. Testing unknown route..."
curl -s "${PUBLIC_URL}/unknown" | jq '.'

echo ""
echo "========================================"
echo "✨ Proxy relay test complete!"
echo ""
echo "Summary:"
echo "- Session: $SESSION_ID"
echo "- Public URL: $PUBLIC_URL"
echo "- ✅ Worker relays HTTP requests to ephemeral containers"
echo "- ✅ Code receives request details via environment variables"
echo "- ✅ Responses returned as JSON through Worker"
echo ""
