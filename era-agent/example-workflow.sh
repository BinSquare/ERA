#!/bin/bash
# Complete workflow: Create VM → Run Code → Get Results → Clean Up

set -e

BASE_URL="${BASE_URL:-http://localhost:8787}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== ERA Agent Workflow Example ===${NC}\n"

# Step 1: Create a Python VM
echo -e "${YELLOW}Step 1: Creating Python VM...${NC}"
CREATE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/vm" \
    -H "Content-Type: application/json" \
    -d '{
        "language": "python",
        "cpu_count": 1,
        "memory_mib": 256,
        "network_mode": "none"
    }')

VM_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')
echo -e "${GREEN}✓ VM Created: $VM_ID${NC}\n"

# Step 2: Run some Python code
echo -e "${YELLOW}Step 2: Running Python code...${NC}"
RUN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/vm/$VM_ID/run" \
    -H "Content-Type: application/json" \
    -d '{
        "command": "python -c \"import sys; print('"'"'Hello from ERA Agent!'"'"'); print(f'"'"'Python version: {sys.version}'"'"'); result = 40 + 2; print(f'"'"'The answer is: {result}'"'"')\"",
        "timeout": 30
    }')

echo -e "${GREEN}✓ Code executed${NC}"
echo -e "\n${BLUE}Output:${NC}"
echo "$RUN_RESPONSE" | jq -r '.stdout'

EXIT_CODE=$(echo "$RUN_RESPONSE" | jq -r '.exit_code')
echo -e "${GREEN}Exit Code: $EXIT_CODE${NC}\n"

# Step 3: Run another command
echo -e "${YELLOW}Step 3: Running more code...${NC}"
RUN_RESPONSE2=$(curl -s -X POST "$BASE_URL/api/vm/$VM_ID/run" \
    -H "Content-Type: application/json" \
    -d '{
        "command": "python -c \"for i in range(5): print(f'"'"'Count: {i}'"'"')\"",
        "timeout": 30
    }')

echo -e "${GREEN}✓ Code executed${NC}"
echo -e "\n${BLUE}Output:${NC}"
echo "$RUN_RESPONSE2" | jq -r '.stdout'

# Step 4: Check VM details
echo -e "\n${YELLOW}Step 4: Getting VM details...${NC}"
VM_DETAILS=$(curl -s "$BASE_URL/api/vm/$VM_ID")
echo "$VM_DETAILS" | jq '{id, language, status, cpu_count, memory_mib, created_at, last_run_at}'

# Step 5: Clean up
echo -e "\n${YELLOW}Step 5: Cleaning up...${NC}"
DELETE_RESPONSE=$(curl -s -X DELETE "$BASE_URL/api/vm/$VM_ID")
echo -e "${GREEN}✓ VM deleted${NC}\n"

echo -e "${GREEN}=== Workflow Complete! ===${NC}\n"

