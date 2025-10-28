#!/bin/bash
# Quick test for lodash (no types)

API_URL="https://era-agent.yawnxyz.workers.dev"
TIMESTAMP=$(date +%s)
session_id="test-lodash-simple-${TIMESTAMP}"

echo "📦 Testing Node.js with lodash (no @types)..."

# Create session
response=$(curl -s -X POST "$API_URL/api/sessions" \
    -H "Content-Type: application/json" \
    -d "{
        \"language\": \"node\",
        \"session_id\": \"$session_id\",
        \"persistent\": true,
        \"setup\": {
            \"npm\": [\"lodash\"]
        }
    }")

echo "$response" | jq '{id, setup_status}'

# Wait for setup
echo "⏳ Waiting for setup..."
for i in {1..60}; do
    sleep 5
    status=$(curl -s "$API_URL/api/sessions/$session_id" | jq -r '.setup_status // "unknown"')
    echo "   Status: $status ($((i*5))s elapsed)"

    if [ "$status" = "completed" ]; then
        echo "✅ Setup completed!"

        # Test it
        echo "Testing lodash..."
        result=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
            -H "Content-Type: application/json" \
            -d '{"code": "const _ = require(\"lodash\");\nconst arr = [1, 2, 3, 4, 5, 6];\nconsole.log(\"chunk:\", _.chunk(arr, 2));\nconsole.log(\"sum:\", _.sum(arr));\nconsole.log(\"version:\", _.VERSION);"}')

        echo "$result" | jq -r '.stdout'

        if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
            echo "✅ LODASH WORKS!"
        else
            echo "❌ Failed"
        fi
        exit 0
    fi

    if [ "$status" = "failed" ]; then
        echo "❌ Setup failed"
        curl -s "$API_URL/api/sessions/$session_id" | jq '.setup_result'
        exit 1
    fi
done

echo "⚠️  Timed out after 5 minutes"
