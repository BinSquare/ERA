#!/bin/bash
# ERA Agent - Cloudflare Deployment Script
# Helps you deploy to Cloudflare Containers (Beta)

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== ERA Agent - Cloudflare Deployment ===${NC}\n"
echo -e "${YELLOW}⚠️  Cloudflare Containers is in BETA${NC}"
echo -e "${YELLOW}⚠️  APIs may change without notice${NC}\n"

# Check if we're in the cloudflare directory
if [ ! -f "wrangler.toml" ]; then
    echo -e "${RED}Error: Run this script from the cloudflare/ directory${NC}"
    exit 1
fi

# Step 1: Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js not found${NC}"
    echo "Install Node.js from https://nodejs.org/"
    exit 1
fi
echo -e "${GREEN}✓ Node.js found: $(node --version)${NC}"

# Check npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}✗ npm not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ npm found: $(npm --version)${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo "Install Docker from https://docker.com/"
    exit 1
fi
echo -e "${GREEN}✓ Docker found: $(docker --version)${NC}"

# Step 2: Install dependencies
echo -e "\n${BLUE}Step 2: Installing dependencies...${NC}"
if [ ! -d "node_modules" ]; then
    npm install
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Dependencies already installed${NC}"
fi

# Step 3: Check wrangler login
echo -e "\n${BLUE}Step 3: Checking Cloudflare authentication...${NC}"
if npx wrangler whoami &> /dev/null; then
    echo -e "${GREEN}✓ Logged in to Cloudflare${NC}"
    npx wrangler whoami
else
    echo -e "${YELLOW}⚠ Not logged in to Cloudflare${NC}"
    echo "Running: npx wrangler login"
    npx wrangler login
fi

# Step 4: Check Docker image configuration
echo -e "\n${BLUE}Step 4: Checking configuration...${NC}"

# Check if wrangler.toml has been updated
if grep -q "YOUR_DOCKERHUB_USERNAME" wrangler.toml 2>/dev/null || \
   grep -q "YOUR_REGISTRY_USERNAME" wrangler.toml 2>/dev/null; then
    echo -e "${RED}✗ Please update wrangler.toml with your Docker Hub username${NC}"
    echo ""
    echo "Edit wrangler.toml and replace:"
    echo "  YOUR_DOCKERHUB_USERNAME/era-agent:latest"
    echo "with:"
    echo "  your-actual-username/era-agent:latest"
    exit 1
fi

# Extract image name from wrangler.toml
IMAGE=$(grep "image = " wrangler.toml | sed 's/.*image = "\(.*\)"/\1/')
echo -e "${GREEN}✓ Docker image: ${IMAGE}${NC}"

# Step 5: Verify Docker image exists
echo -e "\n${BLUE}Step 5: Checking if Docker image exists...${NC}"
if docker pull "$IMAGE" &> /dev/null; then
    echo -e "${GREEN}✓ Docker image found and pulled${NC}"
else
    echo -e "${RED}✗ Docker image not found: $IMAGE${NC}"
    echo ""
    echo "Build and push your image first:"
    echo "  cd ../era-agent"
    echo "  docker build -t $IMAGE ."
    echo "  docker push $IMAGE"
    exit 1
fi

# Step 6: Deploy
echo -e "\n${BLUE}Step 6: Deploying to Cloudflare...${NC}"
echo -e "${YELLOW}This may take a few moments...${NC}"

if npx wrangler deploy; then
    echo -e "\n${GREEN}✓ Deployment successful!${NC}"
    
    # Get the worker URL
    echo -e "\n${BLUE}Your worker is deployed!${NC}"
    echo ""
    echo "Test it with:"
    echo "  curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health"
    echo ""
    echo "View docs:"
    echo "  https://era-agent.YOUR_SUBDOMAIN.workers.dev/docs"
    echo ""
    echo "Monitor logs:"
    echo "  npx wrangler tail"
else
    echo -e "\n${RED}✗ Deployment failed${NC}"
    echo "Check the error messages above"
    exit 1
fi

# Step 7: Quick test
echo -e "\n${BLUE}Step 7: Would you like to tail logs? (y/n)${NC}"
read -r response
if [ "$response" = "y" ]; then
    echo -e "${YELLOW}Starting log tail... (Ctrl+C to stop)${NC}"
    npx wrangler tail
fi

echo -e "\n${GREEN}=== Deployment Complete! ===${NC}\n"

