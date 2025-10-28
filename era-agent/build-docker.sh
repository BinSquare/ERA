#!/bin/bash
# Quick build script for ERA Agent Docker image

set -e

echo "Building ERA Agent Docker image..."
docker build -t era-agent:latest .

echo ""
echo "✓ Build complete!"
echo ""
echo "Next steps:"
echo "  1. Run locally:       docker run -d -p 8787:8787 era-agent:latest"
echo "  2. Use Compose:       docker-compose up -d"
echo "  3. For Cloudflare:    docker tag era-agent:latest your-registry/era-agent:latest"
echo "                        docker push your-registry/era-agent:latest"
echo ""
