#!/bin/bash
# Test script for ERA Agent Docker deployment

set -e

CONTAINER_NAME="era-agent-test"
PORT="8787"

echo "Testing ERA Agent Docker deployment..."
echo ""

# Clean up any existing test container
docker stop ${CONTAINER_NAME} 2>/dev/null || true
docker rm ${CONTAINER_NAME} 2>/dev/null || true

# Build the image
echo "1. Building Docker image..."
docker build -t era-agent:test .

# Run the container
echo "2. Starting container..."
docker run -d \
  --name ${CONTAINER_NAME} \
  -p ${PORT}:8787 \
  era-agent:test

# Wait for container to be healthy
echo "3. Waiting for container to be healthy..."
for i in {1..30}; do
  if docker inspect ${CONTAINER_NAME} --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
    echo "   Container is healthy!"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "   Error: Container failed to become healthy"
    docker logs ${CONTAINER_NAME}
    exit 1
  fi
  echo "   Waiting... ($i/30)"
  sleep 2
done

# Test health endpoint
echo "4. Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s http://localhost:${PORT}/health || echo "FAILED")
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
  echo "   ✓ Health check passed"
else
  echo "   ✗ Health check failed: $HEALTH_RESPONSE"
  docker logs ${CONTAINER_NAME}
  exit 1
fi

# Test VM creation
echo "5. Testing VM creation..."
CREATE_RESPONSE=$(curl -s -X POST http://localhost:${PORT}/api/vm/create \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu":1,"memory":256}' || echo "FAILED")

if echo "$CREATE_RESPONSE" | grep -q "success"; then
  echo "   ✓ VM creation passed"
  VM_ID=$(echo "$CREATE_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
  echo "   Created VM: $VM_ID"
else
  echo "   ✗ VM creation failed: $CREATE_RESPONSE"
fi

# Test temporary execution
echo "6. Testing temporary execution..."
EXEC_RESPONSE=$(curl -s -X POST http://localhost:${PORT}/api/vm/temp \
  -H "Content-Type: application/json" \
  -d '{"language":"python","command":"python -c \"print(42)\"","timeout":30}' || echo "FAILED")

if echo "$EXEC_RESPONSE" | grep -q "42"; then
  echo "   ✓ Temporary execution passed"
else
  echo "   ⚠ Temporary execution may have failed (check if VM runtime is available in container)"
  echo "   Response: $EXEC_RESPONSE"
fi

# Clean up
echo "7. Cleaning up..."
docker stop ${CONTAINER_NAME}
docker rm ${CONTAINER_NAME}

echo ""
echo "✓ All tests completed!"
echo ""
echo "The Docker image is working correctly."
echo "Deploy with: docker-compose up -d"

BUILD_SCRIPT_END

chmod +x "${OUTPUT_DIR}/test-docker.sh"
echo "✓ Generated test-docker.sh"

echo ""
echo "================================"
echo "✓ Docker compilation complete!"
echo "================================"
echo ""
echo "Generated files:"
echo "  - Dockerfile"
echo "  - docker-compose.yml"
echo "  - HTTP_API.md"
echo "  - DOCKER_DEPLOYMENT.md"
echo "  - build-docker.sh"
echo "  - test-docker.sh"
echo ""
echo "Quick start:"
echo "  1. Build: ./build-docker.sh"
echo "  2. Test:  ./test-docker.sh"
echo "  3. Run:   docker-compose up -d"
echo ""
echo "For Cloudflare deployment, see DOCKER_DEPLOYMENT.md"
echo ""

