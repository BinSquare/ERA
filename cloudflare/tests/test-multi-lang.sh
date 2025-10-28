#!/bin/bash
# Comprehensive multi-language project upload tests
# Tests JS, TS, Deno, and Python projects with both bash and python upload scripts

set -e

API_URL="${ERA_API_URL:-https://anewera.dev}"
TIMESTAMP=$(date +%s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ERA Agent Multi-Language Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Track results
PASSED=0
FAILED=0
declare -a FAILED_TESTS

# Helper function to wait for setup
wait_for_setup() {
  local session_id=$1
  local max_wait=90
  local wait_count=0

  echo -e "${YELLOW}   Waiting for package installation...${NC}"

  while [ $wait_count -lt $max_wait ]; do
    STATUS=$(curl -s "$API_URL/api/sessions/$session_id" | jq -r '.setup_status')

    if [ "$STATUS" = "completed" ]; then
      echo -e "${GREEN}   ✅ Packages installed!${NC}"
      return 0
    elif [ "$STATUS" = "failed" ]; then
      echo -e "${RED}   ❌ Package installation failed!${NC}"
      curl -s "$API_URL/api/sessions/$session_id" | jq '.setup_result'
      return 1
    fi

    sleep 2
    wait_count=$((wait_count + 2))
  done

  echo -e "${RED}   ❌ Timeout waiting for setup${NC}"
  return 1
}

# Test function
test_project() {
  local test_name=$1
  local lang=$2
  local project_dir=$3
  local run_code=$4
  local upload_script=$5
  local has_setup=$6

  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}Test: $test_name${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local session_id="test-${lang}-${TIMESTAMP}"

  # Step 1: Create session
  echo -e "${YELLOW}1. Creating session...${NC}"

  if [ "$has_setup" = "true" ]; then
    # Create with setup
    if [ "$lang" = "python" ]; then
      REQUIREMENTS=$(cat "$project_dir/requirements.txt")
      curl -s -X POST "$API_URL/api/sessions" \
        -H "Content-Type: application/json" \
        -d '{
          "language": "'"$lang"'",
          "session_id": "'"$session_id"'",
          "persistent": true,
          "setup": {
            "pip": {
              "requirements": "'"$REQUIREMENTS"'"
            }
          }
        }' | jq -r '.id' > /dev/null
    else
      # Node/TS - use npm array format
      curl -s -X POST "$API_URL/api/sessions" \
        -H "Content-Type: application/json" \
        -d '{
          "language": "'"$lang"'",
          "session_id": "'"$session_id"'",
          "persistent": true,
          "setup": {
            "npm": ["lodash", "axios"]
          }
        }' > /dev/null 2>&1
    fi

    # Wait for setup
    if ! wait_for_setup "$session_id"; then
      FAILED=$((FAILED + 1))
      FAILED_TESTS+=("$test_name - Setup failed")
      return 1
    fi
  else
    # No setup needed (Deno)
    curl -s -X POST "$API_URL/api/sessions" \
      -H "Content-Type: application/json" \
      -d '{
        "language": "'"$lang"'",
        "session_id": "'"$session_id"'",
        "persistent": true
      }' | jq -r '.id' > /dev/null
  fi

  echo -e "${GREEN}   ✅ Session created: $session_id${NC}"

  # Step 2: Upload files
  echo -e "${YELLOW}2. Uploading files with $upload_script...${NC}"

  if [ "$upload_script" = "bash" ]; then
    if ./era-upload.sh "$session_id" "$project_dir" "$API_URL" > /tmp/upload_output.log 2>&1; then
      echo -e "${GREEN}   ✅ Files uploaded via bash script${NC}"
    else
      echo -e "${RED}   ❌ Upload failed${NC}"
      cat /tmp/upload_output.log
      FAILED=$((FAILED + 1))
      FAILED_TESTS+=("$test_name - Upload failed")
      return 1
    fi
  else
    if python3 ./era_upload.py "$session_id" "$project_dir" "$API_URL" > /tmp/upload_output.log 2>&1; then
      echo -e "${GREEN}   ✅ Files uploaded via Python script${NC}"
    else
      echo -e "${RED}   ❌ Upload failed${NC}"
      cat /tmp/upload_output.log
      FAILED=$((FAILED + 1))
      FAILED_TESTS+=("$test_name - Upload failed")
      return 1
    fi
  fi

  # Step 3: List files
  echo -e "${YELLOW}3. Verifying uploaded files...${NC}"
  FILE_COUNT=$(curl -s "$API_URL/api/sessions/$session_id/files" | jq '.files | length')
  echo -e "${GREEN}   ✅ Found $FILE_COUNT files${NC}"

  # Step 4: Run code
  echo -e "${YELLOW}4. Running code...${NC}"

  RUN_RESULT=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
    -H "Content-Type: application/json" \
    -d "{\"code\": \"$run_code\"}")

  EXIT_CODE=$(echo "$RUN_RESULT" | jq -r '.exit_code')
  STDOUT=$(echo "$RUN_RESULT" | jq -r '.stdout')

  echo "   Exit code: $EXIT_CODE"
  echo "   Output:"
  echo "$STDOUT" | sed 's/^/     /'

  # Check for success marker
  if [ "$EXIT_CODE" = "0" ] && echo "$STDOUT" | grep -q "test passed"; then
    echo -e "${GREEN}   ✅ Code executed successfully!${NC}"
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}   ❌ Code execution failed!${NC}"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("$test_name - Execution failed")
  fi

  # Cleanup (optional - leave for inspection)
  # curl -s -X DELETE "$API_URL/api/sessions/$session_id" > /dev/null
}

# Run Tests

echo -e "${BLUE}Starting test suite...${NC}"
echo ""

# Test 1: JavaScript with bash script
test_project \
  "JavaScript (Bash upload)" \
  "node" \
  "/tmp/era-tests/js-project" \
  "require('./index.js')" \
  "bash" \
  "true"

# Test 2: JavaScript with Python script
test_project \
  "JavaScript (Python upload)" \
  "node" \
  "/tmp/era-tests/js-project" \
  "require('./index.js')" \
  "python" \
  "true"

# Test 3: TypeScript with bash script
test_project \
  "TypeScript (Bash upload)" \
  "typescript" \
  "/tmp/era-tests/ts-project" \
  "require('./index.ts')" \
  "bash" \
  "true"

# Test 4: Python with Python script
test_project \
  "Python (Python upload)" \
  "python" \
  "/tmp/era-tests/py-project" \
  "exec(open('main.py').read())" \
  "python" \
  "true"

# Test 5: Deno with bash script (no dependencies)
test_project \
  "Deno (Bash upload)" \
  "deno" \
  "/tmp/era-tests/deno-project" \
  "/usr/local/bin/deno run --allow-read main.ts" \
  "bash" \
  "false"

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Passed: $PASSED${NC}"
echo -e "${RED}❌ Failed: $FAILED${NC}"

if [ $FAILED -gt 0 ]; then
  echo ""
  echo -e "${RED}Failed tests:${NC}"
  for test in "${FAILED_TESTS[@]}"; do
    echo -e "${RED}  • $test${NC}"
  done
fi

echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}🎉 All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
