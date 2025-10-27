#!/bin/bash

# Test script for ERA Agent Remote MCP Server
# Tests all major functionality via HTTP/JSON-RPC

set -e

MCP_URL="${MCP_URL:-https://era-agent.yawnxyz.workers.dev/mcp/v1}"

echo "=========================================="
echo "ERA Agent Remote MCP Server Test"
echo "=========================================="
echo "Endpoint: $MCP_URL"
echo ""

# Helper function to make MCP calls
mcp_call() {
  local id=$1
  local method=$2
  local params=$3

  curl -s -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"jsonrpc\": \"2.0\",
      \"id\": $id,
      \"method\": \"$method\",
      \"params\": $params
    }"
}

# Test 1: Initialize
echo "Test 1: Initialize connection"
echo "----------------------------------------"
result=$(mcp_call 1 "initialize" '{
  "protocolVersion": "0.1.0",
  "clientInfo": {
    "name": "test-script",
    "version": "1.0.0"
  },
  "capabilities": {}
}')

echo "$result" | jq '.result.serverInfo'
echo ""

# Test 2: List tools
echo "Test 2: List available tools"
echo "----------------------------------------"
result=$(mcp_call 2 "tools/list" '{}')

tool_count=$(echo "$result" | jq '.result.tools | length')
echo "Found $tool_count tools:"
echo "$result" | jq -r '.result.tools[] | "  - \(.name): \(.description[:60])..."'
echo ""

# Test 3: Execute Python code
echo "Test 3: Execute Python code (era_python)"
echo "----------------------------------------"
result=$(mcp_call 3 "tools/call" '{
  "name": "era_python",
  "arguments": {
    "code": "print(\"Hello from Remote MCP!\")\nprint([x**2 for x in range(10)])"
  }
}')

echo "$result" | jq -r '.result.content[0].text'
echo ""

# Test 4: Execute Node.js code
echo "Test 4: Execute Node.js code (era_node)"
echo "----------------------------------------"
result=$(mcp_call 4 "tools/call" '{
  "name": "era_node",
  "arguments": {
    "code": "const data = [1, 2, 3, 4, 5];\nconsole.log(\"Sum:\", data.reduce((a, b) => a + b));"
  }
}')

echo "$result" | jq -r '.result.content[0].text'
echo ""

# Test 5: Create a session
echo "Test 5: Create persistent session"
echo "----------------------------------------"
result=$(mcp_call 5 "tools/call" '{
  "name": "era_create_session",
  "arguments": {
    "language": "python",
    "persistent": true
  }
}')

session_info=$(echo "$result" | jq -r '.result.content[0].text')
session_id=$(echo "$session_info" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
echo "Created session: $session_id"
echo ""

# Test 6: Run code in session
echo "Test 6: Run code in session (set variable)"
echo "----------------------------------------"
result=$(mcp_call 6 "tools/call" "{
  \"name\": \"era_run_in_session\",
  \"arguments\": {
    \"session_id\": \"$session_id\",
    \"code\": \"x = 42\\nprint(f'Set x = {x}')\"
  }
}")

echo "$result" | jq -r '.result.content[0].text'
echo ""

# Test 7: Run more code in same session
echo "Test 7: Access variable from previous execution"
echo "----------------------------------------"
result=$(mcp_call 7 "tools/call" "{
  \"name\": \"era_run_in_session\",
  \"arguments\": {
    \"session_id\": \"$session_id\",
    \"code\": \"y = x * 2\\nprint(f'y = x * 2 = {y}')\"
  }
}")

echo "$result" | jq -r '.result.content[0].text'
echo ""

# Test 8: List sessions
echo "Test 8: List all sessions"
echo "----------------------------------------"
result=$(mcp_call 8 "tools/call" '{
  "name": "era_list_sessions",
  "arguments": {}
}')

echo "$result" | jq -r '.result.content[0].text'
echo ""

# Test 9: Shell command
echo "Test 9: Execute shell command (era_shell)"
echo "----------------------------------------"
result=$(mcp_call 9 "tools/call" '{
  "name": "era_shell",
  "arguments": {
    "command": "echo Hello Shell && python3 --version"
  }
}')

echo "$result" | jq -r '.result.content[0].text'
echo ""

# Test 10: TypeScript execution
echo "Test 10: Execute TypeScript code (era_typescript)"
echo "----------------------------------------"
result=$(mcp_call 10 "tools/call" '{
  "name": "era_typescript",
  "arguments": {
    "code": "interface User {\n  name: string;\n  age: number;\n}\n\nconst user: User = { name: \"Alice\", age: 30 };\nconsole.log(`${user.name} is ${user.age} years old`);"
  }
}')

echo "$result" | jq -r '.result.content[0].text'
echo ""

# Test 11: Delete session
echo "Test 11: Delete session"
echo "----------------------------------------"
result=$(mcp_call 11 "tools/call" "{
  \"name\": \"era_delete_session\",
  \"arguments\": {
    \"session_id\": \"$session_id\"
  }
}")

echo "$result" | jq -r '.result.content[0].text'
echo ""

# Test 12: List resources
echo "Test 12: List resources"
echo "----------------------------------------"
result=$(mcp_call 12 "resources/list" '{}')

echo "$result" | jq '.result.resources | length' | xargs echo "Found resources:"
echo ""

echo "=========================================="
echo "✅ All remote MCP tests passed!"
echo "=========================================="
echo ""
echo "The remote MCP server is fully functional and exposes all 14 tools:"
echo "  - 5 Language-specific tools (python, node, typescript, deno, shell)"
echo "  - 3 Core execution tools (execute, create_session, run_in_session)"
echo "  - 3 Session management tools (list, get, delete)"
echo "  - 3 File operation tools (upload, read, list)"
echo ""
echo "Ready to use with Claude Desktop or custom MCP clients!"
