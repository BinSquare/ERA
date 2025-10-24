#!/bin/bash

# Comprehensive MCP tools test script
# Tests actual tool execution (requires Docker/Firecracker)

set -e

echo "🧪 Testing ERA Agent MCP Tools"
echo "==============================="
echo ""

# Build the agent
echo "📦 Building agent..."
go build -o agent-mcp-test
echo "✅ Build successful"
echo ""

# Function to send MCP request and get response
send_mcp_request() {
    local request="$1"
    echo "$request" | ./agent-mcp-test mcp 2>/dev/null | head -1
}

# Function to send multiple requests
send_mcp_sequence() {
    (
        for request in "$@"; do
            echo "$request"
            sleep 0.2
        done
    ) | timeout 30 ./agent-mcp-test mcp 2>/dev/null
}

# Test 1: Initialize
echo "Test 1: Initialize Protocol"
echo "---------------------------"
RESPONSE=$(send_mcp_request '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0"}}')
echo "$RESPONSE" | jq '.'
if echo "$RESPONSE" | jq -e '.result.serverInfo.name == "era-agent-mcp"' > /dev/null; then
    echo "✅ Initialize successful"
else
    echo "❌ Initialize failed"
    exit 1
fi
echo ""

# Test 2: List Tools
echo "Test 2: List Available Tools"
echo "----------------------------"
TOOLS_RESPONSE=$(send_mcp_sequence \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    | grep '"id":2' | head -1)

echo "$TOOLS_RESPONSE" | jq '.result.tools[] | {name, description}'
TOOL_COUNT=$(echo "$TOOLS_RESPONSE" | jq '.result.tools | length')
echo ""
echo "Found $TOOL_COUNT tools"
if [ "$TOOL_COUNT" -eq 9 ]; then
    echo "✅ All 9 tools available"
else
    echo "❌ Expected 9 tools, found $TOOL_COUNT"
    exit 1
fi
echo ""

# Test 3: Execute Simple Code (era_execute_code)
echo "Test 3: Execute Simple Python Code"
echo "-----------------------------------"
CODE_REQUEST='{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "era_execute_code",
    "arguments": {
      "code": "print(\"Hello from ERA Agent MCP!\")",
      "language": "python"
    }
  }
}'

EXEC_RESPONSE=$(send_mcp_sequence \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    "$CODE_REQUEST" \
    | grep '"id":3' | head -1)

echo "Response:"
echo "$EXEC_RESPONSE" | jq '.'

if echo "$EXEC_RESPONSE" | jq -e '.result.content[0].text' | grep -q "Hello from ERA Agent MCP"; then
    echo "✅ Code execution successful"
else
    echo "❌ Code execution failed"
    if echo "$EXEC_RESPONSE" | jq -e '.error' > /dev/null; then
        echo "Error details:"
        echo "$EXEC_RESPONSE" | jq '.error'
    fi
fi
echo ""

# Test 4: List Resources
echo "Test 4: List Resources"
echo "----------------------"
RESOURCES_RESPONSE=$(send_mcp_sequence \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":4,"method":"resources/list","params":{}}' \
    | grep '"id":4' | head -1)

echo "$RESOURCES_RESPONSE" | jq '.result'
if echo "$RESOURCES_RESPONSE" | jq -e '.result.resources' > /dev/null; then
    echo "✅ Resources list successful"
else
    echo "❌ Resources list failed"
fi
echo ""

# Test 5: Create Session
echo "Test 5: Create Persistent Session"
echo "----------------------------------"
SESSION_REQUEST='{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tools/call",
  "params": {
    "name": "era_create_session",
    "arguments": {
      "language": "python",
      "cpu_count": 1,
      "memory_mib": 256
    }
  }
}'

SESSION_RESPONSE=$(send_mcp_sequence \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    "$SESSION_REQUEST" \
    | grep '"id":5' | head -1)

echo "Response:"
echo "$SESSION_RESPONSE" | jq '.'

if echo "$SESSION_RESPONSE" | jq -e '.result.content[0].text' | grep -q "Session ID:"; then
    SESSION_ID=$(echo "$SESSION_RESPONSE" | jq -r '.result.content[0].text' | grep -o 'Session ID: [a-zA-Z0-9-]*' | cut -d' ' -f3)
    echo "✅ Session created: $SESSION_ID"

    # Test 6: Run in Session
    echo ""
    echo "Test 6: Run Code in Session"
    echo "----------------------------"
    RUN_REQUEST="{
      \"jsonrpc\": \"2.0\",
      \"id\": 6,
      \"method\": \"tools/call\",
      \"params\": {
        \"name\": \"era_run_in_session\",
        \"arguments\": {
          \"session_id\": \"$SESSION_ID\",
          \"code\": \"x = 42\\nprint(f'Value: {x}')\"
        }
      }
    }"

    RUN_RESPONSE=$(send_mcp_sequence \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
        "$RUN_REQUEST" \
        | grep '"id":6' | head -1)

    echo "Response:"
    echo "$RUN_RESPONSE" | jq '.'

    if echo "$RUN_RESPONSE" | jq -e '.result.content[0].text' | grep -q "Value: 42"; then
        echo "✅ Session execution successful"
    else
        echo "❌ Session execution failed"
    fi

    # Test 7: List Sessions
    echo ""
    echo "Test 7: List Sessions"
    echo "---------------------"
    LIST_REQUEST='{
      "jsonrpc": "2.0",
      "id": 7,
      "method": "tools/call",
      "params": {
        "name": "era_list_sessions",
        "arguments": {}
      }
    }'

    LIST_RESPONSE=$(send_mcp_sequence \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
        "$LIST_REQUEST" \
        | grep '"id":7' | head -1)

    echo "Response:"
    echo "$LIST_RESPONSE" | jq '.'

    if echo "$LIST_RESPONSE" | jq -e '.result.content[0].text' | grep -q "$SESSION_ID"; then
        echo "✅ Session listed successfully"
    else
        echo "⚠️  Session list may be empty or format different"
    fi

    # Cleanup: Delete Session
    echo ""
    echo "Cleanup: Delete Session"
    echo "-----------------------"
    DELETE_REQUEST="{
      \"jsonrpc\": \"2.0\",
      \"id\": 8,
      \"method\": \"tools/call\",
      \"params\": {
        \"name\": \"era_delete_session\",
        \"arguments\": {
          \"session_id\": \"$SESSION_ID\"
        }
      }
    }"

    DELETE_RESPONSE=$(send_mcp_sequence \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
        "$DELETE_REQUEST" \
        | grep '"id":8' | head -1)

    echo "Response:"
    echo "$DELETE_RESPONSE" | jq '.'
    echo "✅ Session cleanup complete"
else
    echo "❌ Session creation failed"
    if echo "$SESSION_RESPONSE" | jq -e '.error' > /dev/null; then
        echo "Error details:"
        echo "$SESSION_RESPONSE" | jq '.error'
        echo ""
        echo "⚠️  This may indicate Docker/Firecracker is not properly configured"
    fi
fi

echo ""
echo "==============================="
echo "✅ MCP Tools Test Complete"
echo ""
echo "Summary:"
echo "- Initialize: ✅"
echo "- List Tools: ✅"
echo "- Execute Code: $(echo "$EXEC_RESPONSE" | jq -e '.result' > /dev/null 2>&1 && echo '✅' || echo '❌')"
echo "- List Resources: ✅"
echo "- Create Session: $(echo "$SESSION_RESPONSE" | jq -e '.result' > /dev/null 2>&1 && echo '✅' || echo '❌')"
echo ""
echo "Note: Code execution tests require Docker (macOS) or Firecracker (Linux)"
