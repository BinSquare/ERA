#!/bin/bash
# Simple storage test

API_URL="${API_URL:-http://localhost:8787}"

echo "Creating session..."
SESSION=$(curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{"language": "python"}')

SESSION_ID=$(echo $SESSION | jq -r '.session_id')
echo "Session: $SESSION_ID"
echo ""

echo "Testing KV storage..."
curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import era_storage\nera_storage.kv.set(\"demo\", \"test\", \"Hello Storage!\")\nvalue = era_storage.kv.get(\"demo\", \"test\")\nprint(f\"Stored and retrieved: {value}\")"
  }' | jq -r '.stdout'

echo ""
echo "Listing resources..."
curl -s "$API_URL/api/resources/stats" | jq '.'
