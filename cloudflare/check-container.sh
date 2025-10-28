#!/bin/bash

# Check ERA Agent Container Status
# This script checks if the container is provisioned and ready

URL="https://era-agent.yawnxyz.workers.dev/health"
MAX_ATTEMPTS=20
WAIT_TIME=15

echo "🔍 Checking ERA Agent container status..."
echo "URL: $URL"
echo ""

for i in $(seq 1 $MAX_ATTEMPTS); do
    echo "[$i/$MAX_ATTEMPTS] Checking..."
    
    RESPONSE=$(curl -s "$URL" 2>&1)
    
    # Check if we got a successful response
    if echo "$RESPONSE" | grep -q '"status"'; then
        echo ""
        echo "✅ SUCCESS! Container is ready!"
        echo ""
        echo "Response:"
        echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
        echo ""
        echo "🎉 Your ERA Agent is fully operational!"
        echo ""
        echo "Try these commands:"
        echo "  # List VMs"
        echo "  curl $URL/../api/vms"
        echo ""
        echo "  # Create a VM"
        echo "  curl -X POST $URL/../api/vm -H 'Content-Type: application/json' -d '{\"language\":\"python\"}'"
        echo ""
        exit 0
    elif echo "$RESPONSE" | grep -q "provisioning"; then
        echo "   ⏳ Still provisioning... (this can take 2-5 minutes on first deployment)"
    else
        echo "   ⚠️  Unexpected response:"
        echo "   $RESPONSE" | head -n 1
    fi
    
    if [ $i -lt $MAX_ATTEMPTS ]; then
        echo "   Waiting $WAIT_TIME seconds before next check..."
        echo ""
        sleep $WAIT_TIME
    fi
done

echo ""
echo "⚠️  Container is taking longer than expected to provision."
echo ""
echo "This can happen if:"
echo "  - Cloudflare is experiencing high load"
echo "  - Your container image is very large"
echo "  - There's an issue with the deployment"
echo ""
echo "You can:"
echo "  1. Keep waiting and try again: curl $URL"
echo "  2. Check the Cloudflare dashboard for status"
echo "  3. View logs: cd /Users/janzheng/Desktop/Projects/ERA/cloudflare && npx wrangler tail"
echo ""
exit 1

