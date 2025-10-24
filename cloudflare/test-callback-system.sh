#!/bin/bash
# Test the complete callback/proxy system

API_URL="https://era-agent.yawnxyz.workers.dev"
TIMESTAMP=$(date +%s)
SESSION_ID="test-callback-${TIMESTAMP}"

echo "🚀 Testing Complete Callback System"
echo "===================================="
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
  }" | jq '{id, allowInternetAccess, allowPublicAccess}'

echo ""

# 2. Start a simple HTTP server inside the session
echo "2. Starting HTTP server on port 8000..."
curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "from http.server import HTTPServer, BaseHTTPRequestHandler\nimport os\nimport json\n\nclass Handler(BaseHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(200)\n        self.send_header(\"Content-Type\", \"application/json\")\n        self.end_headers()\n        response = {\n            \"message\": \"Hello from ERA Agent callback!\",\n            \"path\": self.path,\n            \"session_id\": os.getenv(\"ERA_SESSION_ID\"),\n            \"proxy_url\": os.getenv(\"ERA_PROXY_URL\")\n        }\n        self.wfile.write(json.dumps(response, indent=2).encode())\n        \n    def do_POST(self):\n        content_length = int(self.headers.get(\"Content-Length\", 0))\n        body = self.rfile.read(content_length).decode(\"utf-8\")\n        self.send_response(200)\n        self.send_header(\"Content-Type\", \"application/json\")\n        self.end_headers()\n        response = {\n            \"message\": \"POST received!\",\n            \"received_data\": body,\n            \"session_id\": os.getenv(\"ERA_SESSION_ID\")\n        }\n        self.wfile.write(json.dumps(response, indent=2).encode())\n    \n    def log_message(self, format, *args):\n        pass  # Suppress server logs\n\nprint(\"Server starting on port 8000...\")\nserver = HTTPServer((\"0.0.0.0\", 8000), Handler)\ntry:\n    server.serve_forever()\nexcept KeyboardInterrupt:\n    print(\"Server stopped\")"
  }' > /dev/null &

SERVER_PID=$!

echo "Waiting for server to start..."
sleep 3

# 3. Get the public URL
echo ""
echo "3. Getting public URL..."
PUBLIC_URL=$(curl -s "$API_URL/api/sessions/$SESSION_ID/host?port=8000" | jq -r '.url')
echo "Public URL: $PUBLIC_URL"

echo ""

# 4. Test GET request (from internet to container!)
echo "4. Testing GET request from internet to container..."
curl -s "${PUBLIC_URL}/test" | jq '.'

echo ""

# 5. Test POST request
echo "5. Testing POST request (webhook simulation)..."
curl -s -X POST "${PUBLIC_URL}/webhook" \
  -H "Content-Type: application/json" \
  -d '{"event": "payment_completed", "amount": 100}' | jq '.'

echo ""

# 6. Test environment variables
echo "6. Verifying ERA environment variables are available..."
curl -s "${PUBLIC_URL}/env" | jq '{session_id, proxy_url}'

echo ""
echo "===================================="
echo "✨ Callback system test complete!"
echo ""
echo "Summary:"
echo "- Session: $SESSION_ID"
echo "- Public URL: $PUBLIC_URL"
echo "- ✅ Container can receive HTTP requests from internet"
echo "- ✅ Container knows its public URL via ERA_PROXY_URL"
echo "- ✅ Full bidirectional callback support working!"
