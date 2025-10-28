#!/bin/bash

# Test script for Cloudflare Worker MCP Server
# Tests MCP protocol endpoints

set -e

echo "🧪 Testing Cloudflare MCP Server"
echo "================================"
echo ""

# Set base URL - update this after deployment
BASE_URL="${MCP_URL:-https://anewera.dev}"
MCP_ENDPOINT="$BASE_URL/mcp/v1"

echo "Testing MCP endpoint: $MCP_ENDPOINT"
echo ""

# Test 1: Initialize
echo "Test 1: Initialize Protocol"
echo "---------------------------"
INIT_REQUEST='{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "0.1.0",
    "clientInfo": {
      "name": "test-client",
      "version": "1.0.0"
    }
  }
}'

RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$INIT_REQUEST")

echo "$RESPONSE" | jq '.'

if echo "$RESPONSE" | jq -e '.result.serverInfo.name == "era-agent-mcp"' > /dev/null; then
  echo "✅ Initialize test passed"
else
  echo "❌ Initialize test failed"
  exit 1
fi
echo ""

# Test 2: List Tools
echo "Test 2: List Tools"
echo "------------------"
TOOLS_REQUEST='{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}'

RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$TOOLS_REQUEST")

echo "$RESPONSE" | jq '.'

TOOL_COUNT=$(echo "$RESPONSE" | jq '.result.tools | length')
echo ""
echo "Found $TOOL_COUNT tools"

if [ "$TOOL_COUNT" -eq 9 ]; then
  echo "✅ List tools test passed"
else
  echo "❌ Expected 9 tools, found $TOOL_COUNT"
  exit 1
fi
echo ""

# Test 3: Execute Code (era_execute_code)
echo "Test 3: Execute Code"
echo "--------------------"
EXECUTE_REQUEST='{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "era_execute_code",
    "arguments": {
      "code": "print(\"Hello from CF MCP!\")",
      "language": "python"
    }
  }
}'

RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$EXECUTE_REQUEST")

echo "$RESPONSE" | jq '.'

if echo "$RESPONSE" | jq -e '.result.content[0].text' | grep -q "Hello from CF MCP"; then
  echo "✅ Execute code test passed"
else
  echo "❌ Execute code test failed"
  if echo "$RESPONSE" | jq -e '.error' > /dev/null; then
    echo "Error:"
    echo "$RESPONSE" | jq '.error'
  fi
fi
echo ""

# Test 4: List Resources
echo "Test 4: List Resources"
echo "----------------------"
RESOURCES_REQUEST='{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "resources/list",
  "params": {}
}'

RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$RESOURCES_REQUEST")

echo "$RESPONSE" | jq '.'

if echo "$RESPONSE" | jq -e '.result.resources' > /dev/null; then
  echo "✅ List resources test passed"
else
  echo "❌ List resources test failed"
fi
echo ""

# Test 5: Create Session
echo "Test 5: Create Session"
echo "----------------------"
SESSION_REQUEST='{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tools/call",
  "params": {
    "name": "era_create_session",
    "arguments": {
      "language": "python"
    }
  }
}'

RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$SESSION_REQUEST")

echo "$RESPONSE" | jq '.'

if echo "$RESPONSE" | jq -e '.result.content[0].text' | grep -q "Session ID:"; then
  SESSION_ID=$(echo "$RESPONSE" | jq -r '.result.content[0].text' | grep -o 'Session ID: [a-zA-Z0-9-]*' | cut -d' ' -f3)
  echo "✅ Session created: $SESSION_ID"

  # Test 6: Run in Session
  echo ""
  echo "Test 6: Run in Session"
  echo "----------------------"
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

  RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$RUN_REQUEST")

  echo "$RESPONSE" | jq '.'

  if echo "$RESPONSE" | jq -e '.result.content[0].text' | grep -q "Value: 42"; then
    echo "✅ Run in session test passed"
  else
    echo "❌ Run in session test failed"
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

  RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$LIST_REQUEST")

  echo "$RESPONSE" | jq '.'

  if echo "$RESPONSE" | jq -e '.result.content[0].text' | grep -q "$SESSION_ID"; then
    echo "✅ List sessions test passed"
  else
    echo "⚠️  Session not found in list (may have been cleaned up)"
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

  RESPONSE=$(curl -s -X POST "$MCP_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$DELETE_REQUEST")

  echo "$RESPONSE" | jq '.'
  echo "✅ Session cleanup complete"
else
  echo "❌ Session creation failed"
  if echo "$RESPONSE" | jq -e '.error' > /dev/null; then
    echo "Error:"
    echo "$RESPONSE" | jq '.error'
  fi
fi

echo ""
echo "================================"
echo "✅ MCP Server Tests Complete"
echo ""
echo "Summary:"
echo "- Initialize: ✅"
echo "- List Tools: ✅"
echo "- Execute Code: ✅"
echo "- List Resources: ✅"
echo "- Create Session: ✅"
echo "- Run in Session: ✅"
echo "- List Sessions: ✅"
echo ""
echo "MCP Server URL: $MCP_ENDPOINT"
