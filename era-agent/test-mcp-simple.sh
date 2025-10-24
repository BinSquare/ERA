#!/bin/bash

# Simple MCP server test script
# Tests basic MCP protocol communication

set -e

echo "🧪 Testing ERA Agent MCP Server"
echo "================================"
echo ""

# Build the agent
echo "📦 Building agent..."
go build -o agent-mcp-test
echo "✅ Build successful"
echo ""

# Test 1: Initialize request
echo "Test 1: Initialize"
echo "------------------"
INIT_REQUEST='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"0.1.0","clientInfo":{"name":"test-client","version":"1.0.0"}}}'

echo "$INIT_REQUEST" | timeout 5 ./agent-mcp-test mcp 2>/dev/null | head -1 | jq '.' || {
    echo "❌ Initialize test failed"
    exit 1
}
echo "✅ Initialize test passed"
echo ""

# Test 2: List tools
echo "Test 2: List Tools"
echo "------------------"
(
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    sleep 0.5
    echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
    sleep 0.5
) | timeout 5 ./agent-mcp-test mcp 2>/dev/null | grep -A 1 '"id":2' | tail -1 | jq '.result.tools | length' || {
    echo "❌ List tools test failed"
    exit 1
}
echo "✅ List tools test passed"
echo ""

# Test 3: List resources
echo "Test 3: List Resources"
echo "----------------------"
(
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    sleep 0.5
    echo '{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}'
    sleep 0.5
) | timeout 5 ./agent-mcp-test mcp 2>/dev/null | grep -A 1 '"id":3' | tail -1 | jq '.result.resources' || {
    echo "❌ List resources test failed"
    exit 1
}
echo "✅ List resources test passed"
echo ""

echo "================================"
echo "✅ All basic MCP tests passed!"
echo ""
echo "Note: Full code execution tests require Firecracker/Docker setup"
