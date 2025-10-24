#!/bin/bash
# Simple ERA Agent Test

BASE_URL="${1:-http://localhost:8787}"

echo "Testing ERA Agent at: $BASE_URL"
echo ""

# Create VM
echo "Creating VM..."
VM_ID=$(curl -sf -X POST "$BASE_URL/api/vm" \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu_count":1,"memory_mib":256}' | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//')

echo "VM ID: $VM_ID"
echo ""

# Test 1: Simple echo
echo "Test 1: Echo"
curl -sf -X POST "$BASE_URL/api/vm/$VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"echo Hello from ERA","timeout":30}' | jq -r '.stdout'
echo ""

# Test 2: Python version
echo "Test 2: Python version"
curl -sf -X POST "$BASE_URL/api/vm/$VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"python3 --version","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Test 3: Simple Python print
echo "Test 3: Python print"
curl -sf -X POST "$BASE_URL/api/vm/$VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"python3 -c \"print(2+2)\"","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Test 4: Python with imports
echo "Test 4: Python with JSON"
curl -sf -X POST "$BASE_URL/api/vm/$VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"python3 -c \"import json; print(json.dumps({\\\"result\\\": 42}))\"","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Clean up Python VM
curl -sf -X DELETE "$BASE_URL/api/vm/$VM_ID" > /dev/null

# ============================================================================
# Node.js / JavaScript Tests
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Node.js / JavaScript Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create Node VM
echo "Creating Node.js VM..."
NODE_VM_ID=$(curl -sf -X POST "$BASE_URL/api/vm" \
  -H "Content-Type: application/json" \
  -d '{"language":"node","cpu_count":1,"memory_mib":256}' | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//')

echo "Node VM ID: $NODE_VM_ID"
echo ""

# Test 5: Node.js version
echo "Test 5: Node.js version"
curl -sf -X POST "$BASE_URL/api/vm/$NODE_VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"node --version","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Test 6: Simple JavaScript
echo "Test 6: Simple JavaScript"
curl -sf -X POST "$BASE_URL/api/vm/$NODE_VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"node -e \"console.log(2 + 2)\"","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Test 7: JavaScript with JSON
echo "Test 7: JavaScript with JSON"
curl -sf -X POST "$BASE_URL/api/vm/$NODE_VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"node -e \"console.log(JSON.stringify({ result: 42, status: \\\"success\\\" }))\"","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Test 8: JavaScript array operations
echo "Test 8: JavaScript array map/reduce"
curl -sf -X POST "$BASE_URL/api/vm/$NODE_VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"node -e \"const nums = [1,2,3,4,5]; const squared = nums.map(n => n*n); console.log(\\\"Squares:\\\", squared); console.log(\\\"Sum:\\\", squared.reduce((a,b) => a+b, 0))\"","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Test 9: TypeScript-style modern JS
echo "Test 9: Modern JavaScript (ES6+)"
curl -sf -X POST "$BASE_URL/api/vm/$NODE_VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"node -e \"const greet = (name) => \`Hello, \${name}!\`; console.log(greet(\\\"ERA Agent\\\")); const obj = { x: 10, y: 20 }; const { x, y } = obj; console.log(\`Sum: \${x + y}\`)\"","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Test 10: Async/Promise example
echo "Test 10: Async/Promise"
curl -sf -X POST "$BASE_URL/api/vm/$NODE_VM_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"command":"node -e \"(async () => { const delay = ms => new Promise(resolve => setTimeout(resolve, ms)); console.log(\\\"Start\\\"); await delay(100); console.log(\\\"After 100ms\\\"); })()\"","timeout":30}' | jq -r '.stdout,.stderr'
echo ""

# Clean up Node VM
echo "Cleaning up..."
curl -sf -X DELETE "$BASE_URL/api/vm/$NODE_VM_ID"
echo ""
echo "✓ All tests completed!"
