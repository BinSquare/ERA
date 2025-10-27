#!/bin/bash

# Simple test script for the MCP shell tool

echo "====================================="
echo "Testing MCP Shell Tool"
echo "====================================="

echo ""
echo "1. Listing all tools to verify era_run_shell exists..."
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","clientInfo":{"name":"test","version":"1.0.0"}}}' | ./agent mcp 2>&1 | head -1

echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | ./agent mcp 2>&1 | jq -r '.result.tools[] | select(.name == "era_run_shell") | "Found: \(.name) - \(.description)"'

echo ""
echo "2. Testing era_run_shell with echo command (this may take 30+ seconds as it creates a VM)..."
(
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","clientInfo":{"name":"test","version":"1.0.0"}}}'
  sleep 0.1
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"era_run_shell","arguments":{"command":"echo Hello from shell!","timeout":30}}}'
  sleep 0.1
) | timeout 60 ./agent mcp 2>&1 | tail -10

echo ""
echo "====================================="
echo "Test complete!"
echo "====================================="
