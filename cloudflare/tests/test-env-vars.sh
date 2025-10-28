#!/bin/bash
# Test environment variables

API_URL="https://anewera.dev"
TIMESTAMP=$(date +%s)
SESSION_ID="test-env-${TIMESTAMP}"

echo "🧪 Testing Environment Variables"
echo "================================"
echo ""

# Create Python session
echo "Creating Python session..."
curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d "{
    \"language\": \"python\",
    \"session_id\": \"$SESSION_ID\",
    \"persistent\": true
  }" | jq '{id, language}'

echo ""
echo "---"
echo ""

# Test 1: Default environment variables
echo "Test 1: Default environment variables (ERA_SESSION_ID, ERA_LANGUAGE, ERA_SESSION)"
result=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import os\nprint(f\"ERA_SESSION: {os.environ.get('\''ERA_SESSION'\'')}\")  \nprint(f\"ERA_SESSION_ID: {os.environ.get('\''ERA_SESSION_ID'\'')}\")  \nprint(f\"ERA_LANGUAGE: {os.environ.get('\''ERA_LANGUAGE'\'')}\")"
  }')

echo "$result" | jq -r '.stdout'

if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
  echo "✅ Test 1 PASSED"
else
  echo "❌ Test 1 FAILED"
fi

echo ""
echo "---"
echo ""

# Test 2: Custom environment variables
echo "Test 2: Custom environment variables (API_KEY, DATABASE_URL)"
result=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import os\nprint(f\"API_KEY: {os.environ.get('\''API_KEY'\'')}\")  \nprint(f\"DATABASE_URL: {os.environ.get('\''DATABASE_URL'\'')}\")",
    "env": {
      "API_KEY": "secret123",
      "DATABASE_URL": "postgresql://localhost:5432/db"
    }
  }')

echo "$result" | jq -r '.stdout'

if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
  echo "✅ Test 2 PASSED"
else
  echo "❌ Test 2 FAILED"
fi

echo ""
echo "---"
echo ""

# Test 3: Env vars are NOT persisted
echo "Test 3: Env vars are NOT persisted (should be None)"
result=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import os\napi_key = os.environ.get('\''API_KEY'\'')\nif api_key is None:\n    print(\"✅ API_KEY is None - not persisted!\")\nelse:\n    print(f\"❌ API_KEY still exists: {api_key}\")"
  }')

echo "$result" | jq -r '.stdout'

if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
  echo "✅ Test 3 PASSED"
else
  echo "❌ Test 3 FAILED"
fi

echo ""
echo "---"
echo ""

# Test 4: All languages support env vars
echo "Test 4: Node.js environment variables"
curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d "{
    \"language\": \"node\",
    \"session_id\": \"${SESSION_ID}-node\",
    \"persistent\": false
  }" > /dev/null

result=$(curl -s -X POST "$API_URL/api/sessions/${SESSION_ID}-node/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "console.log(\"ERA_SESSION_ID:\", process.env.ERA_SESSION_ID);\nconsole.log(\"API_KEY:\", process.env.API_KEY);",
    "env": {
      "API_KEY": "node-secret"
    }
  }')

echo "$result" | jq -r '.stdout'

if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
  echo "✅ Test 4 PASSED"
else
  echo "❌ Test 4 FAILED"
fi

echo ""
echo "================================"
echo "✨ All tests completed!"
