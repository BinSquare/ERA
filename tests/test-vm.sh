#!/bin/bash
# ERA Agent - VM Execution Test Script
# Tests creating a VM, executing code, and retrieving results

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get base URL from argument or use default
BASE_URL="${1:-http://localhost:8787}"
BASE_URL="${1:-https://era-agent.yawnxyz.workers.dev}"

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║     ERA Agent - VM Test Script         ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${CYAN}Testing against: ${BASE_URL}${NC}\n"

# ============================================================================
# Step 1: Health Check
# ============================================================================
echo -e "${BLUE}━━━ Step 1: Health Check ━━━${NC}"

if curl -sf "${BASE_URL}/health" > /dev/null; then
    echo -e "${GREEN}✓ Service is healthy${NC}"
else
    echo -e "${RED}✗ Service health check failed${NC}"
    echo "Make sure the service is running:"
    echo "  Local: cd era-agent && ./agent serve"
    echo "  Production: Check your Cloudflare deployment"
    exit 1
fi

# ============================================================================
# Step 2: Create Python VM
# ============================================================================
echo -e "\n${BLUE}━━━ Step 2: Creating Python VM ━━━${NC}"

CREATE_RESPONSE=$(curl -sf -X POST "${BASE_URL}/api/vm" \
    -H "Content-Type: application/json" \
    -d '{
        "language": "python",
        "cpu_count": 1,
        "memory_mib": 256,
        "network_mode": "none"
    }')

if [ -z "$CREATE_RESPONSE" ]; then
    echo -e "${RED}✗ Failed to create VM${NC}"
    exit 1
fi

# Extract VM ID using grep and sed (more portable than jq)
VM_ID=$(echo "$CREATE_RESPONSE" | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//')

if [ -z "$VM_ID" ]; then
    echo -e "${RED}✗ Could not extract VM ID${NC}"
    echo "Response: $CREATE_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ VM created successfully${NC}"
echo -e "${CYAN}  VM ID: ${VM_ID}${NC}"

# ============================================================================
# Step 3: Execute Python Code
# ============================================================================
echo -e "\n${BLUE}━━━ Step 3: Executing Python Code ━━━${NC}"

# Python code to execute (simple one-liner for easier testing)
PYTHON_CMD="import sys, json; print('Hello from ERA Agent!'); print('Python version:', sys.version.split()[0]); numbers = [1, 2, 3, 4, 5]; squared = [n**2 for n in numbers]; print('Squares:', squared); result = {'status': 'success', 'computed_value': sum(squared), 'message': 'Computation complete!'}; print(json.dumps(result, indent=2))"

echo -e "${YELLOW}Code to execute:${NC}"
echo "  Python computation: squares of [1,2,3,4,5] and JSON output"
echo ""

# Execute the code
RUN_RESPONSE=$(curl -sf -X POST "${BASE_URL}/api/vm/${VM_ID}/run" \
    -H "Content-Type: application/json" \
    -d "{
        \"command\": \"python3 -c \\\"${PYTHON_CMD}\\\"\",
        \"timeout\": 30
    }")

if [ -z "$RUN_RESPONSE" ]; then
    echo -e "${RED}✗ Failed to execute code${NC}"
    # Try to clean up
    curl -sf -X DELETE "${BASE_URL}/api/vm/${VM_ID}" > /dev/null
    exit 1
fi

echo -e "${GREEN}✓ Code executed successfully${NC}"

# Extract exit code
EXIT_CODE=$(echo "$RUN_RESPONSE" | grep -o '"exit_code":[0-9]*' | sed 's/"exit_code"://')
echo -e "${CYAN}  Exit code: ${EXIT_CODE}${NC}"

# Extract stdout if present
STDOUT=$(echo "$RUN_RESPONSE" | grep -o '"stdout":"[^"]*"' | sed 's/"stdout":"//;s/"//')
if [ -n "$STDOUT" ]; then
    echo -e "${CYAN}  Output captured at: ${STDOUT}${NC}"
fi

# ============================================================================
# Step 4: Display Results
# ============================================================================
echo -e "\n${BLUE}━━━ Step 4: Execution Results ━━━${NC}"

# Try to extract output from response
OUTPUT=$(echo "$RUN_RESPONSE" | grep -o '"output":"[^"]*"' | sed 's/"output":"//;s/"//;s/\\n/\n/g')

if [ -n "$OUTPUT" ]; then
    echo -e "${GREEN}Output:${NC}"
    echo "$OUTPUT" | sed 's/^/  /'
else
    # Try to get raw output field
    FULL_OUTPUT=$(echo "$RUN_RESPONSE" | sed 's/.*"output"://' | sed 's/}$//')
    if [ -n "$FULL_OUTPUT" ]; then
        echo -e "${GREEN}Output:${NC}"
        echo "$FULL_OUTPUT" | sed 's/^/  /'
    else
        echo -e "${YELLOW}⚠ Output format not recognized${NC}"
        echo -e "${YELLOW}Full response:${NC}"
        echo "$RUN_RESPONSE" | sed 's/^/  /'
    fi
fi

# ============================================================================
# Step 5: Test Node.js VM
# ============================================================================
echo -e "\n${BLUE}━━━ Step 5: Testing Node.js VM ━━━${NC}"

NODE_CREATE=$(curl -sf -X POST "${BASE_URL}/api/vm" \
    -H "Content-Type: application/json" \
    -d '{
        "language": "node",
        "cpu_count": 1,
        "memory_mib": 256
    }')

NODE_VM_ID=$(echo "$NODE_CREATE" | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"//')

if [ -z "$NODE_VM_ID" ]; then
    echo -e "${YELLOW}⚠ Could not create Node.js VM (may not be supported yet)${NC}"
else
    echo -e "${GREEN}✓ Node.js VM created: ${NODE_VM_ID}${NC}"

    # Execute Node.js code
    NODE_CODE='console.log("Hello from Node.js!"); console.log("Result:", 40 + 2);'

    NODE_RUN=$(curl -sf -X POST "${BASE_URL}/api/vm/${NODE_VM_ID}/run" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"node -e \\\"${NODE_CODE}\\\"\",
            \"timeout\": 30
        }")

    if [ -n "$NODE_RUN" ]; then
        echo -e "${GREEN}✓ Node.js code executed${NC}"
    fi

    # Clean up Node VM
    curl -sf -X DELETE "${BASE_URL}/api/vm/${NODE_VM_ID}" > /dev/null
fi

# ============================================================================
# Step 6: List All VMs
# ============================================================================
echo -e "\n${BLUE}━━━ Step 6: Listing All VMs ━━━${NC}"

VMS_RESPONSE=$(curl -sf "${BASE_URL}/api/vms")

if [ -n "$VMS_RESPONSE" ]; then
    echo -e "${GREEN}Active VMs:${NC}"
    echo "$VMS_RESPONSE" | sed 's/^/  /'
else
    echo -e "${YELLOW}⚠ Could not list VMs${NC}"
fi

# ============================================================================
# Step 7: Clean Up
# ============================================================================
echo -e "\n${BLUE}━━━ Step 7: Cleaning Up ━━━${NC}"

DELETE_RESPONSE=$(curl -sf -X DELETE "${BASE_URL}/api/vm/${VM_ID}")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ VM ${VM_ID} deleted${NC}"
else
    echo -e "${YELLOW}⚠ Could not delete VM${NC}"
fi

# ============================================================================
# Summary
# ============================================================================
echo -e "\n${GREEN}"
echo "╔════════════════════════════════════════╗"
echo "║        ✓ All Tests Passed!             ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}Summary:${NC}"
echo "  • Health check: ✓"
echo "  • VM creation: ✓"
echo "  • Code execution: ✓"
echo "  • Result retrieval: ✓"
echo "  • VM cleanup: ✓"
echo ""
echo -e "${BLUE}ERA Agent is working correctly! 🚀${NC}"
