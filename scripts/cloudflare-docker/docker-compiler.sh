#!/bin/bash
# ERA Agent Cloudflare Docker Compiler
# Generates Docker configuration for deploying ERA Agent to Cloudflare Containers
# Run from scripts/cloudflare-docker directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ERA_AGENT_DIR="${PROJECT_ROOT}/era-agent"

echo "ERA Agent Cloudflare Docker Compiler"
echo "====================================="
echo ""
echo "Generating Docker configuration for era-agent..."
echo "Templates: ${TEMPLATES_DIR}"
echo "Target: ${ERA_AGENT_DIR}"
echo ""

# Validate directories
if [ ! -d "${ERA_AGENT_DIR}" ]; then
    echo "Error: era-agent directory not found at ${ERA_AGENT_DIR}"
    exit 1
fi

if [ ! -f "${ERA_AGENT_DIR}/main.go" ]; then
    echo "Error: era-agent/main.go not found. Is this the correct ERA project?"
    exit 1
fi

if [ ! -d "${TEMPLATES_DIR}" ]; then
    echo "Error: templates directory not found at ${TEMPLATES_DIR}"
    exit 1
fi

# Copy templates to era-agent
echo "Copying Docker files from templates..."

cp "${TEMPLATES_DIR}/Dockerfile" "${ERA_AGENT_DIR}/Dockerfile"
echo "✓ Copied Dockerfile"

cp "${TEMPLATES_DIR}/docker-compose.yml" "${ERA_AGENT_DIR}/docker-compose.yml"
echo "✓ Copied docker-compose.yml"

# Create .dockerignore if template exists
if [ -f "${TEMPLATES_DIR}/.dockerignore" ]; then
    cp "${TEMPLATES_DIR}/.dockerignore" "${ERA_AGENT_DIR}/.dockerignore"
    echo "✓ Copied .dockerignore"
fi

cp "${TEMPLATES_DIR}/build-docker.sh" "${ERA_AGENT_DIR}/build-docker.sh"
chmod +x "${ERA_AGENT_DIR}/build-docker.sh"
echo "✓ Copied build-docker.sh"

cp "${TEMPLATES_DIR}/test-docker.sh" "${ERA_AGENT_DIR}/test-docker.sh"
chmod +x "${ERA_AGENT_DIR}/test-docker.sh"
echo "✓ Copied test-docker.sh"

cp "${TEMPLATES_DIR}/HTTP_API.md" "${ERA_AGENT_DIR}/HTTP_API.md"
echo "✓ Copied HTTP_API.md"

cp "${TEMPLATES_DIR}/DOCKER_DEPLOYMENT.md" "${ERA_AGENT_DIR}/DOCKER_DEPLOYMENT.md"
echo "✓ Copied DOCKER_DEPLOYMENT.md"

# Update Makefile with Docker targets if not already present
if [ -f "${ERA_AGENT_DIR}/Makefile" ]; then
    if ! grep -q "docker-build:" "${ERA_AGENT_DIR}/Makefile"; then
        echo "" >> "${ERA_AGENT_DIR}/Makefile"
        cat >> "${ERA_AGENT_DIR}/Makefile" << 'MAKEFILE_END'

# Docker targets (added by cloudflare-docker-compiler)
docker-build:
	docker build -t era-agent:latest .

docker-run:
	docker run -d \
		--name era-agent \
		-p 8787:8787 \
		-v era-agent-state:/var/lib/agent \
		era-agent:latest

docker-stop:
	docker stop era-agent || true
	docker rm era-agent || true

docker-clean: docker-stop
	docker rmi era-agent:latest || true
	docker volume rm era-agent-state || true

# Docker Compose targets
docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

docker-logs:
	docker-compose logs -f

# Cloudflare deployment helpers
cf-build:
	@echo "Building for Cloudflare Containers..."
	docker build -t era-agent:cloudflare .
	@echo "Tag and push to your registry:"
	@echo "  docker tag era-agent:cloudflare your-registry/era-agent:latest"
	@echo "  docker push your-registry/era-agent:latest"
MAKEFILE_END
        echo "✓ Added Docker targets to Makefile"
    else
        echo "⚠ Makefile already has Docker targets, skipping..."
    fi
fi

echo ""
echo "================================"
echo "✓ Docker compilation complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "  cd ${ERA_AGENT_DIR}"
echo "  ./build-docker.sh       # Build the Docker image"
echo "  docker-compose up -d    # Run with Docker Compose"
echo ""
echo "Or use Make:"
echo "  make docker-build"
echo "  make docker-up"
echo ""
echo "Documentation:"
echo "  HTTP_API.md              # API reference"
echo "  DOCKER_DEPLOYMENT.md     # Deployment guide"
echo ""

