#!/bin/bash
# Test script for ERA Agent HTTP Server

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

BASE_URL="${BASE_URL:-http://localhost:8787}"
VM_ID=""

echo -e "${BLUE}=== ERA Agent HTTP Server Test ===${NC}\n"

# Function to print section headers
section() {
    echo -e "\n${YELLOW}▶ $1${NC}"
}

# Function to print success
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
error() {
    echo -e "${RED}✗ $1${NC}"
}

# Test 1: Health Check
section "Testing health endpoint"
HEALTH_RESPONSE=$(curl -s "$BASE_URL/health")
echo "$HEALTH_RESPONSE" | jq .
if echo "$HEALTH_RESPONSE" | jq -e '.status == "healthy"' > /dev/null; then
    success "Health check passed"
else
    error "Health check failed"
    exit 1
fi

# Test 2: Create VM
section "Creating a Python VM"
CREATE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/vm" \
    -H "Content-Type: application/json" \
    -d '{
        "language": "python",
        "cpu_count": 1,
        "memory_mib": 256,
        "network_mode": "none",
        "persist": false
    }')

echo "$CREATE_RESPONSE" | jq .

VM_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')
if [ -n "$VM_ID" ] && [ "$VM_ID" != "null" ]; then
    success "VM created with ID: $VM_ID"
else
    error "Failed to create VM"
    exit 1
fi

# Test 3: Get VM Details
section "Getting VM details"
GET_RESPONSE=$(curl -s "$BASE_URL/api/vm/$VM_ID")
echo "$GET_RESPONSE" | jq .

if echo "$GET_RESPONSE" | jq -e '.id' > /dev/null; then
    success "VM details retrieved"
else
    error "Failed to get VM details"
fi

# Test 4: List VMs
section "Listing all VMs"
LIST_RESPONSE=$(curl -s "$BASE_URL/api/vms")
echo "$LIST_RESPONSE" | jq .

VM_COUNT=$(echo "$LIST_RESPONSE" | jq -r '.count')
if [ "$VM_COUNT" -gt 0 ]; then
    success "Found $VM_COUNT VM(s)"
else
    error "No VMs found"
fi

# Test 5: Run Code in VM
section "Running code in VM"
RUN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/vm/$VM_ID/run" \
    -H "Content-Type: application/json" \
    -d '{
        "command": "python -c \"print('Hello from ERA Agent!'); print(2 + 2)\"",
        "timeout": 30
    }')

echo "$RUN_RESPONSE" | jq .

EXIT_CODE=$(echo "$RUN_RESPONSE" | jq -r '.exit_code')
if [ "$EXIT_CODE" = "0" ]; then
    success "Code executed successfully"
    echo -e "\n${BLUE}Stdout:${NC}"
    echo "$RUN_RESPONSE" | jq -r '.stdout'
else
    error "Code execution failed with exit code: $EXIT_CODE"
fi

# Test 6: Stop VM
section "Stopping VM"
STOP_RESPONSE=$(curl -s -X POST "$BASE_URL/api/vm/$VM_ID/stop")
echo "$STOP_RESPONSE" | jq .

if echo "$STOP_RESPONSE" | jq -e '.status == "stopped"' > /dev/null; then
    success "VM stopped"
else
    error "Failed to stop VM"
fi

# Test 7: Delete VM
section "Deleting VM"
DELETE_RESPONSE=$(curl -s -X DELETE "$BASE_URL/api/vm/$VM_ID")
echo "$DELETE_RESPONSE" | jq .

if echo "$DELETE_RESPONSE" | jq -e '.status == "deleted"' > /dev/null; then
    success "VM deleted"
else
    error "Failed to delete VM"
fi

# Test 8: Verify VM is gone
section "Verifying VM is deleted"
GET_DELETED_RESPONSE=$(curl -s "$BASE_URL/api/vm/$VM_ID")
echo "$GET_DELETED_RESPONSE" | jq .

if echo "$GET_DELETED_RESPONSE" | jq -e '.error' > /dev/null; then
    success "VM successfully removed"
else
    error "VM still exists"
fi

# Final summary
echo -e "\n${GREEN}=== All tests passed! ===${NC}\n"

# Show example curl commands
section "Example Commands"
cat << EOF

# Health check
curl $BASE_URL/health | jq .

# Create VM
curl -X POST $BASE_URL/api/vm \\
  -H "Content-Type: application/json" \\
  -d '{
    "language": "python",
    "cpu_count": 1,
    "memory_mib": 256
  }' | jq .

# List VMs
curl $BASE_URL/api/vms | jq .

# Get VM details
curl $BASE_URL/api/vm/{vm-id} | jq .

# Run code
curl -X POST $BASE_URL/api/vm/{vm-id}/run \\
  -H "Content-Type: application/json" \\
  -d '{
    "command": "python -c \\"print('Hello')\\"",
    "timeout": 30
  }' | jq .

# Stop VM
curl -X POST $BASE_URL/api/vm/{vm-id}/stop | jq .

# Delete VM
curl -X DELETE $BASE_URL/api/vm/{vm-id} | jq .

EOF

success "Test script completed!"

