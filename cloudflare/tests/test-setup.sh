#!/bin/bash
# Test script for ERA Agent async setup system
# Tests pip, npm, and Deno package installation

set -e

API_URL="https://era-agent.yawnxyz.workers.dev"
TIMESTAMP=$(date +%s)

echo "🧪 Testing ERA Agent Setup System"
echo "=================================="
echo ""

# Helper function to wait for setup completion
wait_for_setup() {
    local session_id=$1
    local max_wait=${2:-60}
    local waited=0

    echo "⏳ Waiting for setup to complete..."
    while [ $waited -lt $max_wait ]; do
        status=$(curl -s "$API_URL/api/sessions/$session_id" | jq -r '.setup_status // "unknown"')

        if [ "$status" = "completed" ]; then
            echo "✅ Setup completed successfully"
            return 0
        elif [ "$status" = "failed" ]; then
            echo "❌ Setup failed"
            curl -s "$API_URL/api/sessions/$session_id" | jq '.setup_result'
            return 1
        fi

        echo "   Status: $status (${waited}s elapsed)"
        sleep 5
        waited=$((waited + 5))
    done

    echo "⚠️  Setup timed out after ${max_wait}s"
    return 1
}

# Test 1: Python pip packages
echo "📦 Test 1: Python pip packages"
echo "-------------------------------"
session_id="test-pip-${TIMESTAMP}"

echo "Creating session with pip packages: requests, pydantic..."
response=$(curl -s -X POST "$API_URL/api/sessions" \
    -H "Content-Type: application/json" \
    -d "{
        \"language\": \"python\",
        \"session_id\": \"$session_id\",
        \"persistent\": true,
        \"setup\": {
            \"pip\": [\"requests\", \"pydantic\"]
        }
    }")

echo "$response" | jq '{id, setup_status}'

if wait_for_setup "$session_id" 120; then
    echo "Testing installed packages..."
    result=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
        -H "Content-Type: application/json" \
        -d '{"code": "import requests\nimport pydantic\nprint(f\"requests {requests.__version__}\")\nprint(f\"pydantic {pydantic.__version__}\")"}')

    echo "$result" | jq -r '.stdout'

    if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
        echo "✅ Test 1 PASSED"
    else
        echo "❌ Test 1 FAILED"
        echo "$result" | jq
    fi
else
    echo "❌ Test 1 FAILED (setup)"
fi

echo ""
echo ""

# Test 2: Node.js npm packages
echo "📦 Test 2: Node.js npm packages"
echo "-------------------------------"
session_id="test-npm-${TIMESTAMP}"

echo "Creating session with npm packages: ms, chalk..."
response=$(curl -s -X POST "$API_URL/api/sessions" \
    -H "Content-Type: application/json" \
    -d "{
        \"language\": \"node\",
        \"session_id\": \"$session_id\",
        \"persistent\": true,
        \"setup\": {
            \"npm\": [\"ms\", \"chalk\"]
        }
    }")

echo "$response" | jq '{id, setup_status}'

if wait_for_setup "$session_id" 120; then
    echo "Testing installed packages..."
    result=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
        -H "Content-Type: application/json" \
        -d '{"code": "const ms = require(\"ms\");\nconst chalk = require(\"chalk\");\nconsole.log(\"ms:\", ms(\"2 days\"));\nconsole.log(\"chalk loaded:\", typeof chalk.blue);"}')

    echo "$result" | jq -r '.stdout'

    if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
        echo "✅ Test 2 PASSED"
    else
        echo "❌ Test 2 FAILED"
        echo "$result" | jq
    fi
else
    echo "❌ Test 2 FAILED (setup)"
fi

echo ""
echo ""

# Test 3: TypeScript with npm packages
echo "📦 Test 3: TypeScript with npm packages"
echo "---------------------------------------"
session_id="test-ts-npm-${TIMESTAMP}"

echo "Creating TypeScript session with npm packages: lodash..."
response=$(curl -s -X POST "$API_URL/api/sessions" \
    -H "Content-Type: application/json" \
    -d "{
        \"language\": \"typescript\",
        \"session_id\": \"$session_id\",
        \"persistent\": true,
        \"setup\": {
            \"npm\": [\"lodash\", \"@types/lodash\"]
        }
    }")

echo "$response" | jq '{id, setup_status}'

if wait_for_setup "$session_id" 300; then
    echo "Testing installed packages..."
    result=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
        -H "Content-Type: application/json" \
        -d '{"code": "import _ from \"lodash\";\nconst arr = [1, 2, 3, 4];\nconsole.log(\"chunk:\", _.chunk(arr, 2));\nconsole.log(\"sum:\", _.sum(arr));"}')

    echo "$result" | jq -r '.stdout'

    if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
        echo "✅ Test 3 PASSED"
    else
        echo "❌ Test 3 FAILED"
        echo "$result" | jq
    fi
else
    echo "❌ Test 3 FAILED (setup)"
fi

echo ""
echo ""

# Test 4: Deno with npm: imports (no setup needed!)
echo "📦 Test 4: Deno with npm: imports"
echo "---------------------------------"
session_id="test-deno-npm-${TIMESTAMP}"

echo "Creating Deno session (no setup - uses npm: imports)..."
response=$(curl -s -X POST "$API_URL/api/sessions" \
    -H "Content-Type: application/json" \
    -d "{
        \"language\": \"deno\",
        \"session_id\": \"$session_id\",
        \"persistent\": false
    }")

echo "$response" | jq '{id}'

echo "Testing npm: imports with date-fns..."
result=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
    -H "Content-Type: application/json" \
    -d '{"code": "import { format } from \"npm:date-fns@3.0.0\";\nconst formatted = format(new Date(2024, 0, 1), \"yyyy-MM-dd\");\nconsole.log(\"Formatted:\", formatted);"}')

echo "$result" | jq -r '.stdout'

if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
    echo "✅ Test 4 PASSED"
else
    echo "❌ Test 4 FAILED"
    echo "$result" | jq
fi

echo ""
echo ""

# Test 5: Combined setup (pip + custom commands)
echo "📦 Test 5: Combined setup (pip + commands)"
echo "------------------------------------------"
session_id="test-combined-${TIMESTAMP}"

echo "Creating session with pip + custom commands..."
response=$(curl -s -X POST "$API_URL/api/sessions" \
    -H "Content-Type: application/json" \
    -d "{
        \"language\": \"python\",
        \"session_id\": \"$session_id\",
        \"persistent\": true,
        \"setup\": {
            \"pip\": [\"requests\"],
            \"commands\": [
                \"mkdir -p /tmp/data\",
                \"echo 'test,data' > /tmp/data/test.csv\"
            ]
        }
    }")

echo "$response" | jq '{id, setup_status}'

if wait_for_setup "$session_id" 120; then
    echo "Testing pip package + custom files..."
    result=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
        -H "Content-Type: application/json" \
        -d '{"code": "import requests\nimport os\nprint(\"requests:\", requests.__version__)\nprint(\"file exists:\", os.path.exists(\"/tmp/data/test.csv\"))"}')

    echo "$result" | jq -r '.stdout'

    if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
        echo "✅ Test 5 PASSED"
    else
        echo "❌ Test 5 FAILED"
        echo "$result" | jq
    fi
else
    echo "❌ Test 5 FAILED (setup)"
fi

echo ""
echo ""

# Test 6: Node.js with lodash (larger package)
echo "📦 Test 6: Node.js with lodash (larger package)"
echo "-----------------------------------------------"
session_id="test-lodash-${TIMESTAMP}"

echo "Creating Node.js session with lodash..."
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

if wait_for_setup "$session_id" 300; then
    echo "Testing lodash..."
    result=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
        -H "Content-Type: application/json" \
        -d '{"code": "const _ = require(\"lodash\");\nconst arr = [1, 2, 3, 4, 5, 6];\nconsole.log(\"chunk:\", _.chunk(arr, 2));\nconsole.log(\"sum:\", _.sum(arr));\nconsole.log(\"shuffle:\", _.shuffle(arr));"}')

    echo "$result" | jq -r '.stdout'

    if [ $(echo "$result" | jq -r '.exit_code') -eq 0 ]; then
        echo "✅ Test 6 PASSED"
    else
        echo "❌ Test 6 FAILED"
        echo "$result" | jq
    fi
else
    echo "❌ Test 6 FAILED (setup)"
fi

echo ""
echo ""
echo "=================================="
echo "✨ All tests completed!"
echo "=================================="
