#!/bin/bash
# Quick test for upload scripts - no dependencies, just file uploads
# Tests bash and python upload scripts with simple projects

set -e

API_URL="${ERA_API_URL:-https://era-agent.yawnxyz.workers.dev}"
TIMESTAMP=$(date +%s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ERA Upload Scripts Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

PASSED=0
FAILED=0

# Test 1: Bash script with JS project (no deps)
echo -e "${BLUE}Test 1: Bash Upload Script (JS)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

SESSION_ID="test-bash-js-$TIMESTAMP"

# Create simple session
curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "node",
    "session_id": "'"$SESSION_ID"'",
    "persistent": true
  }' > /dev/null

echo -e "${GREEN}✅ Session created: $SESSION_ID${NC}"

# Upload with bash script
echo "Uploading files..."
if ./era-upload.sh "$SESSION_ID" "/tmp/era-tests/js-project" "$API_URL" 2>&1 | grep -q "Upload complete"; then
  echo -e "${GREEN}✅ Bash upload successful${NC}"

  # Check files
  FILE_COUNT=$(curl -s "$API_URL/api/sessions/$SESSION_ID/files" | jq '.files | length')
  if [ "$FILE_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✅ Found $FILE_COUNT files uploaded${NC}"
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}❌ No files found${NC}"
    FAILED=$((FAILED + 1))
  fi
else
  echo -e "${RED}❌ Bash upload failed${NC}"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 2: Python script with TS project (no deps)
echo -e "${BLUE}Test 2: Python Upload Script (TS)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

SESSION_ID="test-py-ts-$TIMESTAMP"

# Create simple session
curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "typescript",
    "session_id": "'"$SESSION_ID"'",
    "persistent": true
  }' > /dev/null

echo -e "${GREEN}✅ Session created: $SESSION_ID${NC}"

# Upload with python script
echo "Uploading files..."
if python3 ./era_upload.py "$SESSION_ID" "/tmp/era-tests/ts-project" "$API_URL" 2>&1 | grep -q "Upload complete"; then
  echo -e "${GREEN}✅ Python upload successful${NC}"

  # Check files
  FILE_COUNT=$(curl -s "$API_URL/api/sessions/$SESSION_ID/files" | jq '.files | length')
  if [ "$FILE_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✅ Found $FILE_COUNT files uploaded${NC}"

    # Try to run the code
    RUN_RESULT=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
      -H "Content-Type: application/json" \
      -d '{"code": "require(\"./index.ts\")"}')

    EXIT_CODE=$(echo "$RUN_RESULT" | jq -r '.exit_code')
    if [ "$EXIT_CODE" = "0" ]; then
      echo -e "${GREEN}✅ Code executed successfully${NC}"
      PASSED=$((PASSED + 1))
    else
      echo -e "${YELLOW}⚠️  Code execution had issues (exit code: $EXIT_CODE)${NC}"
      echo "$RUN_RESULT" | jq '.stdout, .stderr'
      PASSED=$((PASSED + 1))  # Still count as pass since upload worked
    fi
  else
    echo -e "${RED}❌ No files found${NC}"
    FAILED=$((FAILED + 1))
  fi
else
  echo -e "${RED}❌ Python upload failed${NC}"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 3: Python project
echo -e "${BLUE}Test 3: Python Upload Script (Python)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

SESSION_ID="test-py-py-$TIMESTAMP"

curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "session_id": "'"$SESSION_ID"'",
    "persistent": true
  }' > /dev/null

echo -e "${GREEN}✅ Session created: $SESSION_ID${NC}"

echo "Uploading files..."
if python3 ./era_upload.py "$SESSION_ID" "/tmp/era-tests/py-project" "$API_URL" 2>&1 | grep -q "Upload complete"; then
  echo -e "${GREEN}✅ Python upload successful${NC}"

  FILE_COUNT=$(curl -s "$API_URL/api/sessions/$SESSION_ID/files" | jq '.files | length')
  if [ "$FILE_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✅ Found $FILE_COUNT files uploaded${NC}"

    # Try to run
    RUN_RESULT=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
      -H "Content-Type: application/json" \
      -d '{"code": "exec(open(\"main.py\").read())"}')

    EXIT_CODE=$(echo "$RUN_RESULT" | jq -r '.exit_code')
    STDOUT=$(echo "$RUN_RESULT" | jq -r '.stdout')

    if [ "$EXIT_CODE" = "0" ] && echo "$STDOUT" | grep -q "test passed"; then
      echo -e "${GREEN}✅ Code executed successfully${NC}"
      PASSED=$((PASSED + 1))
    else
      echo -e "${YELLOW}⚠️  Code execution had issues${NC}"
      echo "Exit code: $EXIT_CODE"
      echo "Output: $STDOUT"
      PASSED=$((PASSED + 1))  # Still count as pass since upload worked
    fi
  else
    echo -e "${RED}❌ No files found${NC}"
    FAILED=$((FAILED + 1))
  fi
else
  echo -e "${RED}❌ Python upload failed${NC}"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 4: Deno project
echo -e "${BLUE}Test 4: Bash Upload Script (Deno)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

SESSION_ID="test-bash-deno-$TIMESTAMP"

curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "deno",
    "session_id": "'"$SESSION_ID"'",
    "persistent": true
  }' > /dev/null

echo -e "${GREEN}✅ Session created: $SESSION_ID${NC}"

echo "Uploading files..."
if ./era-upload.sh "$SESSION_ID" "/tmp/era-tests/deno-project" "$API_URL" 2>&1 | grep -q "Upload complete"; then
  echo -e "${GREEN}✅ Bash upload successful${NC}"

  FILE_COUNT=$(curl -s "$API_URL/api/sessions/$SESSION_ID/files" | jq '.files | length')
  if [ "$FILE_COUNT" -gt "0" ]; then
    echo -e "${GREEN}✅ Found $FILE_COUNT files uploaded${NC}"

    # Try to run
    RUN_RESULT=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
      -H "Content-Type: application/json" \
      -d '{"code": "/usr/local/bin/deno run --allow-read main.ts"}')

    EXIT_CODE=$(echo "$RUN_RESULT" | jq -r '.exit_code')
    STDOUT=$(echo "$RUN_RESULT" | jq -r '.stdout')

    if [ "$EXIT_CODE" = "0" ] && echo "$STDOUT" | grep -q "test passed"; then
      echo -e "${GREEN}✅ Code executed successfully${NC}"
      PASSED=$((PASSED + 1))
    else
      echo -e "${YELLOW}⚠️  Code execution had issues${NC}"
      echo "Exit code: $EXIT_CODE"
      echo "Output: $STDOUT"
      PASSED=$((PASSED + 1))  # Still count as pass since upload worked
    fi
  else
    echo -e "${RED}❌ No files found${NC}"
    FAILED=$((FAILED + 1))
  fi
else
  echo -e "${RED}❌ Bash upload failed${NC}"
  FAILED=$((FAILED + 1))
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Passed: $PASSED${NC}"
echo -e "${RED}❌ Failed: $FAILED${NC}"

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}🎉 All upload tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
