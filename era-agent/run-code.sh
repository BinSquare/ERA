#!/bin/bash
# Simple script to run code in a VM

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <vm-id> <python-code>"
    echo ""
    echo "Example:"
    echo "  $0 python-123 \"print('hello')\""
    echo "  $0 python-123 \"import sys; print(sys.version)\""
    exit 1
fi

VM_ID="$1"
CODE="$2"
BASE_URL="${BASE_URL:-http://localhost:8787}"

# Escape the code for JSON
CODE_ESCAPED=$(echo "$CODE" | jq -Rs .)

echo "Running code in VM: $VM_ID"
echo "Code: $CODE"
echo ""

RESPONSE=$(curl -s -X POST "$BASE_URL/api/vm/$VM_ID/run" \
    -H "Content-Type: application/json" \
    -d "{
        \"command\": \"python -c $CODE_ESCAPED\",
        \"timeout\": 30
    }")

# Check if we got an error
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "Error: $(echo "$RESPONSE" | jq -r '.error')"
    exit 1
fi

# Show output
echo "=== Output ==="
echo "$RESPONSE" | jq -r '.stdout'

# Show exit code
EXIT_CODE=$(echo "$RESPONSE" | jq -r '.exit_code')
if [ "$EXIT_CODE" != "0" ]; then
    echo ""
    echo "Exit code: $EXIT_CODE"
    echo "=== Stderr ==="
    echo "$RESPONSE" | jq -r '.stderr'
fi

