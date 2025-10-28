#!/bin/bash
# ERA Agent - Build Docker and Deploy to Cloudflare
# This script generates Docker files, builds the image, and deploys to Cloudflare

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_COMPILER="${PROJECT_ROOT}/scripts/cloudflare-docker"
ERA_AGENT="${PROJECT_ROOT}/era-agent"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== ERA Agent - Build & Deploy ===${NC}\n"

# Step 1: Build Astro site
echo -e "${BLUE}Step 1: Building Astro documentation site...${NC}"
cd "${SCRIPT_DIR}/site"
if [ ! -d "node_modules" ]; then
    echo "Installing site dependencies..."
    npm install
fi
npm run build
echo -e "${GREEN}✓ Astro site built${NC}\n"

# Step 2: Generate Docker files
echo -e "${BLUE}Step 2: Generating Docker files...${NC}"
cd "${DOCKER_COMPILER}"
./docker-compiler.sh
echo -e "${GREEN}✓ Docker files generated${NC}\n"

# Step 3: Build Docker image
echo -e "${BLUE}Step 3: Building Docker image...${NC}"
cd "${ERA_AGENT}"
docker build -t era-agent:latest .
echo -e "${GREEN}✓ Docker image built${NC}\n"

# Step 4: Deploy to Cloudflare
echo -e "${BLUE}Step 4: Deploying to Cloudflare...${NC}"
cd "${SCRIPT_DIR}"

# Check if logged in
if ! npx wrangler whoami &> /dev/null; then
    echo -e "${YELLOW}⚠ Not logged in to Cloudflare${NC}"
    echo "Running: npx wrangler login"
    npx wrangler login
fi

# Check if R2 bucket exists
echo "Checking R2 bucket..."
if ! npx wrangler r2 bucket list | grep -q "era-sessions"; then
    echo -e "${YELLOW}⚠ R2 bucket 'era-sessions' not found${NC}"
    echo "Creating R2 bucket..."
    npx wrangler r2 bucket create era-sessions
    echo -e "${GREEN}✓ R2 bucket created${NC}"
fi

# Deploy
npx wrangler deploy

echo -e "\n${GREEN}=== Deployment Complete! ===${NC}\n"
echo "Your ERA Agent is deployed!"
echo ""
echo "Visit the site:"
echo "  https://anewera.dev"
echo ""
echo "View logs:"
echo "  npx wrangler tail"
echo ""

# Cleanup option
read -p "Delete generated Docker files from era-agent? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd "${ERA_AGENT}"
    rm -f Dockerfile docker-compose.yml .dockerignore build-docker.sh test-docker.sh HTTP_API.md DOCKER_DEPLOYMENT.md
    echo -e "${GREEN}✓ Cleaned up Docker files${NC}"
fi

