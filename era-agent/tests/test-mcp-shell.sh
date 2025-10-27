#!/bin/bash

# Test script for the MCP shell tool

echo "====================================="
echo "Testing MCP Shell Tool"
echo "====================================="

# Start MCP server in background
echo "Starting MCP server..."
./agent mcp &
MCP_PID=$!
sleep 2

# Helper function to send JSON-RPC request
send_request() {
    local request="$1"
    echo "$request" | nc -q 1 localhost 3000 2>/dev/null || echo "$request"
}

echo ""
echo "1. Testing tools/list to verify era_run_shell exists..."
REQUEST1='{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {}
}'

echo "$REQUEST1" | ./agent mcp | jq '.result.tools[] | select(.name == "era_run_shell")'

echo ""
echo "2. Testing era_run_shell with simple ls command..."
REQUEST2='{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "era_run_shell",
    "arguments": {
      "command": "ls -la /",
      "timeout": 10
    }
  }
}'

echo "$REQUEST2" | ./agent mcp | jq '.'

echo ""
echo "3. Testing era_run_shell with echo command..."
REQUEST3='{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "era_run_shell",
    "arguments": {
      "command": "echo \"Hello from shell!\"",
      "timeout": 10
    }
  }
}'

echo "$REQUEST3" | ./agent mcp | jq '.'

echo ""
echo "====================================="
echo "Shell tool test complete!"
echo "====================================="

# Cleanup
kill $MCP_PID 2>/dev/null
