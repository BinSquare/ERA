#!/bin/bash
# Test script for multi-file project upload
# Demonstrates complete workflow: create session with deps, upload files, run code

set -e

API_URL="${ERA_API_URL:-https://anewera.dev}"
SESSION_ID="test-multi-file-$(date +%s)"
TEST_PROJECT="/tmp/era-test-project"

echo "======================================"
echo "ERA Agent Multi-File Project Test"
echo "======================================"
echo "Session ID: $SESSION_ID"
echo "API URL: $API_URL"
echo ""

# Step 1: Create session with package.json
echo "1️⃣  Creating session with dependencies..."
PACKAGE_JSON=$(cat "$TEST_PROJECT/package.json" | jq -c .)

curl -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "node",
    "session_id": "'"$SESSION_ID"'",
    "persistent": true,
    "setup": {
      "npm": {
        "packageJson": "'"$PACKAGE_JSON"'"
      }
    }
  }' | jq '.'

# Step 2: Wait for setup to complete
echo ""
echo "2️⃣  Waiting for package installation..."
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  STATUS=$(curl -s "$API_URL/api/sessions/$SESSION_ID" | jq -r '.setup_status')

  if [ "$STATUS" = "completed" ]; then
    echo "✅ Packages installed successfully!"
    break
  elif [ "$STATUS" = "failed" ]; then
    echo "❌ Package installation failed!"
    curl -s "$API_URL/api/sessions/$SESSION_ID" | jq '.setup_result'
    exit 1
  fi

  echo "   Status: $STATUS (${WAIT_COUNT}s)"
  sleep 2
  WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
  echo "❌ Timeout waiting for package installation"
  exit 1
fi

# Step 3: Upload project files using bash script
echo ""
echo "3️⃣  Uploading project files..."
./era-upload.sh "$SESSION_ID" "$TEST_PROJECT" "$API_URL"

# Step 4: List uploaded files
echo ""
echo "4️⃣  Listing uploaded files..."
curl -s "$API_URL/api/sessions/$SESSION_ID/files" | jq '.files[] | .path'

# Step 5: Run the project
echo ""
echo "5️⃣  Running the project..."
RUN_RESULT=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"code": "require(\"./src/index.js\")"}')

echo "$RUN_RESULT" | jq '.'

# Step 6: Check output
echo ""
echo "6️⃣  Checking output..."
STDOUT=$(echo "$RUN_RESULT" | jq -r '.stdout')
EXIT_CODE=$(echo "$RUN_RESULT" | jq -r '.exit_code')

echo "Exit code: $EXIT_CODE"
echo "Output:"
echo "$STDOUT"

# Step 7: Test with lodash (from package.json)
echo ""
echo "7️⃣  Testing lodash dependency..."
curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{"code": "const _ = require(\"lodash\"); console.log(\"Lodash chunk:\", _.chunk([1,2,3,4], 2))"}' \
  | jq '.stdout'

# Step 8: Cleanup
echo ""
echo "8️⃣  Cleanup..."
echo "Session will remain for manual inspection: $SESSION_ID"
echo "To delete: curl -X DELETE $API_URL/api/sessions/$SESSION_ID"

echo ""
echo "======================================"
if [ "$EXIT_CODE" = "0" ]; then
  echo "✅ All tests passed!"
else
  echo "❌ Tests failed with exit code: $EXIT_CODE"
  exit 1
fi
echo "======================================"
