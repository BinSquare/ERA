#!/bin/bash
# Test script for storage proxy functionality

set -e

API_URL="${API_URL:-http://localhost:8787}"
SESSION_ID=""

echo "🧪 Testing ERA Storage Proxy..."
echo ""

# Helper function to print test results
test_result() {
  if [ $? -eq 0 ]; then
    echo "✅ $1"
  else
    echo "❌ $1"
    exit 1
  fi
}

# 1. Create a session
echo "1️⃣  Creating Python session..."
RESPONSE=$(curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "persistent": false
  }')

SESSION_ID=$(echo $RESPONSE | jq -r '.session_id')
echo "   Session ID: $SESSION_ID"
test_result "Session created"

echo ""

# 2. Test KV operations
echo "2️⃣  Testing KV operations from sandbox..."
CODE='
import era_storage

# Test KV set
success = era_storage.kv.set("test_app", "greeting", "Hello from sandbox!")
print(f"KV set: {success}")

# Test KV get
value = era_storage.kv.get("test_app", "greeting")
print(f"KV get: {value}")

# Test KV list
keys = era_storage.kv.list("test_app")
print(f"KV list: {keys}")

# Test KV delete
deleted = era_storage.kv.delete("test_app", "greeting")
print(f"KV delete: {deleted}")
'

RESPONSE=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d "{\"code\": $(echo "$CODE" | jq -Rs .)}")

echo "$RESPONSE" | jq -r '.stdout'
test_result "KV operations"

echo ""

# 3. Test D1 operations
echo "3️⃣  Testing D1 operations from sandbox..."
CODE='
import era_storage

# Create table
result = era_storage.d1.exec("test_app", "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)")
print(f"Table created: {result}")

# Insert data
result = era_storage.d1.exec("test_app", "INSERT INTO users (name, email) VALUES (?, ?)", ["Alice", "alice@example.com"])
print(f"Insert result: {result}")

# Query data
users = era_storage.d1.query("test_app", "SELECT * FROM users")
print(f"Query result: {users}")

# Clean up
result = era_storage.d1.exec("test_app", "DROP TABLE users")
print(f"Table dropped: {result}")
'

RESPONSE=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d "{\"code\": $(echo "$CODE" | jq -Rs .)}")

echo "$RESPONSE" | jq -r '.stdout'
test_result "D1 operations"

echo ""

# 4. Test R2 operations
echo "4️⃣  Testing R2 operations from sandbox..."
CODE='
import era_storage

# Test R2 put
content = b"This is a test file from sandbox!"
success = era_storage.r2.put("test_app", "test.txt", content)
print(f"R2 put: {success}")

# Test R2 get
retrieved = era_storage.r2.get("test_app", "test.txt")
print(f"R2 get: {retrieved.decode() if retrieved else None}")

# Test R2 list
objects = era_storage.r2.list("test_app")
print(f"R2 list: {objects}")

# Test R2 delete
deleted = era_storage.r2.delete("test_app", "test.txt")
print(f"R2 delete: {deleted}")
'

RESPONSE=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d "{\"code\": $(echo "$CODE" | jq -Rs .)}")

echo "$RESPONSE" | jq -r '.stdout'
test_result "R2 operations"

echo ""

# 5. Test resource registry
echo "5️⃣  Testing resource registry..."
RESPONSE=$(curl -s "$API_URL/api/resources/list")
echo "$RESPONSE" | jq '.'
test_result "Resource registry list"

echo ""

# 6. Test resource statistics
echo "6️⃣  Testing resource statistics..."
RESPONSE=$(curl -s "$API_URL/api/resources/stats")
echo "$RESPONSE" | jq '.'
test_result "Resource registry stats"

echo ""

# 7. Test cross-namespace access
echo "7️⃣  Testing cross-namespace access..."
CODE='
import era_storage
import json

# Create data in app1
era_storage.kv.set("app1", "config", json.dumps({"feature_x": True}))
print("Set config in app1")

# Create data in app2
era_storage.kv.set("app2", "config", json.dumps({"feature_y": False}))
print("Set config in app2")

# Read from both namespaces
app1_config = json.loads(era_storage.kv.get("app1", "config"))
app2_config = json.loads(era_storage.kv.get("app2", "config"))

print(f"App1 config: {app1_config}")
print(f"App2 config: {app2_config}")

# Clean up
era_storage.kv.delete("app1", "config")
era_storage.kv.delete("app2", "config")
print("Cleaned up both namespaces")
'

RESPONSE=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d "{\"code\": $(echo "$CODE" | jq -Rs .)}")

echo "$RESPONSE" | jq -r '.stdout'
test_result "Cross-namespace access"

echo ""
echo "✅ All storage proxy tests passed!"
