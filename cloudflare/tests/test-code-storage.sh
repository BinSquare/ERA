#!/bin/bash
# Test code storage feature

API_URL="https://anewera.dev"
TIMESTAMP=$(date +%s)
SESSION_ID="test-code-storage-${TIMESTAMP}"

echo "🧪 Testing Code Storage Feature"
echo "================================"
echo ""

echo "1. Create session"
curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d "{\"language\": \"python\", \"session_id\": \"$SESSION_ID\", \"persistent\": true}" | jq '{id, language}'

echo ""
echo "2. Store code in session"
curl -s -X PUT "$API_URL/api/sessions/$SESSION_ID/code" \
  -H "Content-Type: application/json" \
  -d '{"code": "print(\"Hello from stored code!\")", "description": "Test greeting"}' | jq '.'

echo ""
echo "3. Run without passing code (uses stored)"
curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{}' | jq -r '.stdout'

echo ""
echo "4. Update stored code"
curl -s -X PUT "$API_URL/api/sessions/$SESSION_ID/code" \
  -H "Content-Type: application/json" \
  -d '{"code": "import sys\\nprint(f\\\"Python {sys.version}\\\")\\nprint(\\\"Updated code!\\\")"}' | jq '.'

echo ""
echo "5. Run updated code"
curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{}' | jq -r '.stdout'

echo ""
echo "6. Get stored code details"
curl -s -X GET "$API_URL/api/sessions/$SESSION_ID/code" | jq '{description, code_length, updated_at}'

echo ""
echo "================================"
echo "✨ Test complete!"
