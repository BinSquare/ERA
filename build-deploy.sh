#!/bin/bash
# ERA Agent - Complete Build and Deploy Script
# Builds Go agent, creates Docker container, and deploys to Cloudflare

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║   ERA Agent - Build & Deploy to CF     ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Check if we're in the project root
if [ ! -d "era-agent" ] || [ ! -d "cloudflare" ]; then
    echo -e "${RED}Error: Run this script from ERA-cf-clean/ directory${NC}"
    echo "Expected structure:"
    echo "  ERA-cf-clean/"
    echo "  ├── era-agent/"
    echo "  ├── cloudflare/"
    echo "  └── build-deploy.sh (this script)"
    exit 1
fi

# Parse arguments
SKIP_GO_BUILD=false
SKIP_DEPLOY=false
TAIL_LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-go-build)
            SKIP_GO_BUILD=true
            shift
            ;;
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        --tail)
            TAIL_LOGS=true
            shift
            ;;
        --help)
            echo "Usage: ./build-deploy.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-go-build    Skip building Go agent binary"
            echo "  --skip-deploy      Only build, don't deploy to Cloudflare"
            echo "  --tail             Tail logs after deployment"
            echo "  --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./build-deploy.sh                    # Full build and deploy"
            echo "  ./build-deploy.sh --skip-go-build    # Deploy with existing binary"
            echo "  ./build-deploy.sh --skip-deploy      # Build only, no deploy"
            echo "  ./build-deploy.sh --tail             # Deploy and tail logs"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${YELLOW}⚠️  Cloudflare Containers is in BETA${NC}"
echo -e "${YELLOW}⚠️  APIs may change without notice${NC}\n"

# ============================================================================
# Step 1: Check Prerequisites
# ============================================================================
echo -e "${BLUE}━━━ Step 1: Checking Prerequisites ━━━${NC}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    echo "Install Docker Desktop from https://docker.com/"
    exit 1
fi
echo -e "${GREEN}✓ Docker found: $(docker --version | cut -d' ' -f3)${NC}"

# Check Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker is not running${NC}"
    echo "Start Docker Desktop and try again"
    exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"

# Check Go (only if not skipping build)
if [ "$SKIP_GO_BUILD" = false ]; then
    if ! command -v go &> /dev/null; then
        echo -e "${RED}✗ Go not found${NC}"
        echo "Install Go from https://golang.org/"
        exit 1
    fi
    echo -e "${GREEN}✓ Go found: $(go version | cut -d' ' -f3)${NC}"
fi

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

# ============================================================================
# Step 2: Build Go Agent (optional)
# ============================================================================
if [ "$SKIP_GO_BUILD" = false ]; then
    echo -e "\n${BLUE}━━━ Step 2: Building Go Agent ━━━${NC}"

    cd era-agent

    # Check if Makefile exists
    if [ -f "Makefile" ]; then
        echo "Building with make..."
        if make agent; then
            echo -e "${GREEN}✓ Go agent built successfully${NC}"
        else
            echo -e "${RED}✗ Go build failed${NC}"
            exit 1
        fi
    else
        echo "Building with go build..."
        if go build -o agent .; then
            echo -e "${GREEN}✓ Go agent built successfully${NC}"
        else
            echo -e "${RED}✗ Go build failed${NC}"
            exit 1
        fi
    fi

    # Verify binary exists
    if [ ! -f "agent" ]; then
        echo -e "${RED}✗ agent binary not found after build${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Binary size: $(du -h agent | cut -f1)${NC}"

    cd ..
else
    echo -e "\n${BLUE}━━━ Step 2: Skipping Go Build ━━━${NC}"
    echo -e "${YELLOW}Using existing binary${NC}"

    # Verify binary exists
    if [ ! -f "era-agent/agent" ]; then
        echo -e "${RED}✗ agent binary not found in era-agent/${NC}"
        echo "Run without --skip-go-build to build it"
        exit 1
    fi
fi

# ============================================================================
# Step 3: Verify Docker Build Context
# ============================================================================
echo -e "\n${BLUE}━━━ Step 3: Verifying Docker Build Context ━━━${NC}"

cd era-agent

if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}✗ Dockerfile not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Dockerfile found${NC}"

# Test Docker build locally (quick validation)
echo "Testing Docker build (validation only)..."
if docker build -t era-agent:local-test . &> /tmp/era-docker-build.log; then
    echo -e "${GREEN}✓ Dockerfile is valid${NC}"
    # Clean up test image
    docker rmi era-agent:local-test &> /dev/null || true
else
    echo -e "${RED}✗ Docker build failed${NC}"
    echo "Check the log:"
    tail -20 /tmp/era-docker-build.log
    exit 1
fi

cd ..

# ============================================================================
# Step 4: Prepare Cloudflare Worker
# ============================================================================
echo -e "\n${BLUE}━━━ Step 4: Preparing Cloudflare Worker ━━━${NC}"

cd cloudflare

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing npm dependencies..."
    npm install
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Dependencies already installed${NC}"
fi

# Verify wrangler.toml
if [ ! -f "wrangler.toml" ]; then
    echo -e "${RED}✗ wrangler.toml not found${NC}"
    exit 1
fi

# Check configuration
IMAGE_PATH=$(grep "image = " wrangler.toml | sed 's/.*image = "\(.*\)"/\1/')
echo -e "${GREEN}✓ Configuration: image = ${IMAGE_PATH}${NC}"

# ============================================================================
# Step 5: Check Cloudflare Authentication
# ============================================================================
echo -e "\n${BLUE}━━━ Step 5: Checking Cloudflare Authentication ━━━${NC}"

if npx wrangler whoami &> /dev/null; then
    echo -e "${GREEN}✓ Logged in to Cloudflare${NC}"
    ACCOUNT=$(npx wrangler whoami 2>&1 | grep "Account Name" | cut -d':' -f2 | xargs)
    if [ -n "$ACCOUNT" ]; then
        echo -e "${GREEN}  Account: $ACCOUNT${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Not logged in to Cloudflare${NC}"
    echo "Opening browser for authentication..."
    npx wrangler login

    # Verify login succeeded
    if ! npx wrangler whoami &> /dev/null; then
        echo -e "${RED}✗ Login failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Successfully logged in${NC}"
fi

# ============================================================================
# Step 6: Deploy to Cloudflare
# ============================================================================
if [ "$SKIP_DEPLOY" = false ]; then
    echo -e "\n${BLUE}━━━ Step 6: Deploying to Cloudflare ━━━${NC}"
    echo -e "${YELLOW}This will:${NC}"
    echo -e "${YELLOW}  1. Build Docker image from ../era-agent/Dockerfile${NC}"
    echo -e "${YELLOW}  2. Push to Cloudflare's container registry${NC}"
    echo -e "${YELLOW}  3. Deploy Worker with container binding${NC}"
    echo -e "${YELLOW}  (This may take 2-5 minutes...)${NC}\n"

    # Deploy with wrangler
    if npx wrangler deploy; then
        echo -e "\n${GREEN}"
        echo "╔════════════════════════════════════════╗"
        echo "║     ✓ Deployment Successful!          ║"
        echo "╚════════════════════════════════════════╝"
        echo -e "${NC}"

        # Try to get worker URL
        WORKER_NAME=$(grep "name = " wrangler.toml | head -1 | sed 's/.*name = "\(.*\)"/\1/')
        echo -e "${BLUE}Your ERA Agent is deployed!${NC}\n"
        echo "Test endpoints:"
        echo -e "  ${GREEN}Health check:${NC}"
        echo "    curl https://${WORKER_NAME}.YOUR_SUBDOMAIN.workers.dev/health"
        echo ""
        echo -e "  ${GREEN}Create VM:${NC}"
        echo "    curl -X POST https://${WORKER_NAME}.YOUR_SUBDOMAIN.workers.dev/api/vm \\"
        echo "      -H 'Content-Type: application/json' \\"
        echo "      -d '{\"language\":\"python\",\"cpu_count\":1,\"memory_mib\":256}'"
        echo ""
        echo -e "${BLUE}Useful commands:${NC}"
        echo "  View logs:     cd cloudflare && npx wrangler tail"
        echo "  Redeploy:      cd cloudflare && npx wrangler deploy"
        echo "  Check status:  cd cloudflare && npx wrangler whoami"

    else
        echo -e "\n${RED}"
        echo "╔════════════════════════════════════════╗"
        echo "║     ✗ Deployment Failed                ║"
        echo "╚════════════════════════════════════════╝"
        echo -e "${NC}"
        echo "Check the error messages above"
        echo ""
        echo "Common issues:"
        echo "  • Cloudflare Containers not enabled (still in beta)"
        echo "  • Docker build error - check era-agent/Dockerfile"
        echo "  • Network connectivity issues"
        echo "  • Wrangler authentication expired"
        exit 1
    fi

    # ============================================================================
    # Step 7: Optional - Tail Logs
    # ============================================================================
    if [ "$TAIL_LOGS" = true ]; then
        echo -e "\n${BLUE}━━━ Step 7: Tailing Logs ━━━${NC}"
        echo -e "${YELLOW}Press Ctrl+C to stop${NC}\n"
        sleep 2
        npx wrangler tail
    fi

else
    echo -e "\n${BLUE}━━━ Step 6: Skipping Deployment ━━━${NC}"
    echo -e "${GREEN}✓ Build completed successfully${NC}"
    echo ""
    echo "To deploy manually:"
    echo "  cd cloudflare && npx wrangler deploy"
fi

cd ..

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ All steps completed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
