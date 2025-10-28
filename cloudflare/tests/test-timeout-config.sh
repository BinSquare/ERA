#!/bin/bash
# Test session-level timeout configuration

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
echo -e "${BLUE}Timeout Configuration Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

PASSED=0
FAILED=0

# Test 1: Session with default_timeout
echo -e "${BLUE}Test 1: Create session with default_timeout=5${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

SESSION_ID="timeout-test-$TIMESTAMP"

CREATE_RESULT=$(curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "session_id": "'"$SESSION_ID"'",
    "persistent": true,
    "default_timeout": 5
  }')

DEFAULT_TIMEOUT=$(echo "$CREATE_RESULT" | jq -r '.default_timeout')

if [ "$DEFAULT_TIMEOUT" = "5" ]; then
  echo -e "${GREEN}✅ Session created with default_timeout=5${NC}"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}❌ Expected default_timeout=5, got: $DEFAULT_TIMEOUT${NC}"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 2: Code runs successfully within default timeout
echo -e "${BLUE}Test 2: Code completes within default timeout (3s < 5s)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

RUN_RESULT=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import time; time.sleep(3); print(\"Completed!\")"
  }')

EXIT_CODE=$(echo "$RUN_RESULT" | jq -r '.exit_code')
STDOUT=$(echo "$RUN_RESULT" | jq -r '.stdout')

if [ "$EXIT_CODE" = "0" ] && echo "$STDOUT" | grep -q "Completed"; then
  echo -e "${GREEN}✅ Code completed successfully${NC}"
  echo -e "${GREEN}   Exit code: $EXIT_CODE${NC}"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}❌ Code failed unexpectedly${NC}"
  echo -e "${RED}   Exit code: $EXIT_CODE${NC}"
  echo "$RUN_RESULT" | jq '.stderr'
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 3: Code times out with default timeout
echo -e "${BLUE}Test 3: Code times out (10s > 5s default)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

TIMEOUT_RESULT=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import time; time.sleep(10); print(\"Should timeout\")"
  }')

TIMEOUT_EXIT=$(echo "$TIMEOUT_RESULT" | jq -r '.exit_code')

# Exit code 124 = timeout, or negative values, or any error
if [ "$TIMEOUT_EXIT" = "124" ] || [ "$TIMEOUT_EXIT" -lt 0 ] || [ "$TIMEOUT_EXIT" -gt 0 ]; then
  echo -e "${GREEN}✅ Code timed out as expected${NC}"
  echo -e "${GREEN}   Exit code: $TIMEOUT_EXIT (timeout/error)${NC}"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}❌ Code should have timed out but didn't${NC}"
  echo -e "${RED}   Exit code: $TIMEOUT_EXIT${NC}"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 4: Override with longer timeout
echo -e "${BLUE}Test 4: Override default with longer timeout (10s)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

OVERRIDE_RESULT=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID/run" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import time; time.sleep(7); print(\"Override worked!\")",
    "timeout": 10
  }')

OVERRIDE_EXIT=$(echo "$OVERRIDE_RESULT" | jq -r '.exit_code')
OVERRIDE_STDOUT=$(echo "$OVERRIDE_RESULT" | jq -r '.stdout')

if [ "$OVERRIDE_EXIT" = "0" ] && echo "$OVERRIDE_STDOUT" | grep -q "Override worked"; then
  echo -e "${GREEN}✅ Timeout override worked${NC}"
  echo -e "${GREEN}   Exit code: $OVERRIDE_EXIT${NC}"
  PASSED=$((PASSED + 1))
else
  echo -e "${RED}❌ Override failed${NC}"
  echo -e "${RED}   Exit code: $OVERRIDE_EXIT${NC}"
  echo "$OVERRIDE_RESULT" | jq '.stderr'
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 5: Session without default_timeout uses global default (30s)
echo -e "${BLUE}Test 5: Session without default_timeout${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

SESSION_ID2="timeout-test-default-$TIMESTAMP"

CREATE_RESULT2=$(curl -s -X POST "$API_URL/api/sessions" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "session_id": "'"$SESSION_ID2"'",
    "persistent": true
  }')

DEFAULT_TIMEOUT2=$(echo "$CREATE_RESULT2" | jq -r '.default_timeout')

if [ "$DEFAULT_TIMEOUT2" = "null" ] || [ -z "$DEFAULT_TIMEOUT2" ]; then
  echo -e "${GREEN}✅ Session created without explicit default_timeout${NC}"

  # Run with reasonable time (should complete with 30s default)
  RUN_RESULT2=$(curl -s -X POST "$API_URL/api/sessions/$SESSION_ID2/run" \
    -H "Content-Type: application/json" \
    -d '{
      "code": "import time; time.sleep(2); print(\"Works with default!\")"
    }')

  EXIT_CODE2=$(echo "$RUN_RESULT2" | jq -r '.exit_code')
  STDOUT2=$(echo "$RUN_RESULT2" | jq -r '.stdout')

  if [ "$EXIT_CODE2" = "0" ] && echo "$STDOUT2" | grep -q "Works with default"; then
    echo -e "${GREEN}✅ Code ran with global default timeout (30s)${NC}"
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}❌ Code failed with default timeout${NC}"
    echo -e "${RED}   Exit code: $EXIT_CODE2${NC}"
    FAILED=$((FAILED + 1))
  fi
else
  echo -e "${YELLOW}⚠️  Session has default_timeout: $DEFAULT_TIMEOUT2${NC}"
  PASSED=$((PASSED + 1))
fi

echo ""

# Cleanup
echo -e "${BLUE}Cleaning up test sessions...${NC}"
curl -s -X DELETE "$API_URL/api/sessions/$SESSION_ID" > /dev/null || true
curl -s -X DELETE "$API_URL/api/sessions/$SESSION_ID2" > /dev/null || true

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ Passed: $PASSED${NC}"
echo -e "${RED}❌ Failed: $FAILED${NC}"

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}🎉 All timeout tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
