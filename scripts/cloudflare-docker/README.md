# Cloudflare Docker Compiler for ERA Agent

Generates Docker configuration for deploying ERA Agent to Docker, Docker Compose, and Cloudflare Containers.

## Quick Start

```bash
cd scripts/cloudflare-docker
./docker-compiler.sh
cd ../../era-agent
docker-compose up -d
```

Done! ERA Agent is now running at http://localhost:8787

## What It Does

Copies template files to `era-agent/`:
- `Dockerfile` - Multi-stage build (Go → Runtime with Python, Node.js, Deno, Go)
- `docker-compose.yml` - Local development setup with health checks
- `build-docker.sh` - Quick build script
- `test-docker.sh` - Automated integration tests
- `HTTP_API.md` - Complete API documentation
- `DOCKER_DEPLOYMENT.md` - Deployment guide for Docker and Cloudflare
- Adds Docker targets to `Makefile`

## Usage

### Generate Files
```bash
./docker-compiler.sh
```

### Build & Run
```bash
cd ../../era-agent
./build-docker.sh
docker-compose up -d
```

### Test
```bash
curl http://localhost:8787/health

# Run Python code
curl -X POST http://localhost:8787/api/vm/temp \
  -H "Content-Type: application/json" \
  -d '{"language":"python","command":"python -c \"print(42)\"","timeout":30}'
```

### Make Commands
```bash
make docker-build    # Build image
make docker-up       # Start with Compose
make docker-down     # Stop
make docker-logs     # View logs
make docker-clean    # Clean everything
make cf-build        # Build for Cloudflare
```

## Architecture

**Build:** Go → Runtime (2 stages)
- Stage 1: Build Go binary (golang:1.21-alpine, CGO_ENABLED=0)
- Stage 2: Runtime with Python 3.11, Node.js 20, Deno, Go (debian:12-slim)
- Final image: ~380MB

**Key Features:**
- Non-root user (UID 1000) for security
- Persistent volumes for VM state
- Health checks built-in
- Auto-restart on failure

## Configuration

Edit `era-agent/docker-compose.yml`:

```yaml
environment:
  - AGENT_LOG_LEVEL=debug      # Log level (debug, info, warn, error)
  - ERA_API_KEY=your-key        # Optional authentication
  - PORT=8787                   # Server port
  - AGENT_STATE_DIR=/var/lib/agent  # State directory
```

## API Quick Reference

```bash
# Create persistent VM
curl -X POST http://localhost:8787/api/vm/create \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu":1,"memory":256}'

# Execute in VM (use vm_id from create response)
curl -X POST http://localhost:8787/api/vm/execute \
  -H "Content-Type: application/json" \
  -d '{"vm_id":"VM_ID","command":"python -c \"print(42)\"","timeout":30}'

# List VMs
curl http://localhost:8787/api/vm/list

# Stop VM
curl -X POST http://localhost:8787/api/vm/stop \
  -H "Content-Type: application/json" \
  -d '{"vm_id":"VM_ID"}'

# Clean VM
curl -X POST http://localhost:8787/api/vm/clean \
  -H "Content-Type: application/json" \
  -d '{"vm_id":"VM_ID"}'
```

See `era-agent/HTTP_API.md` (after generation) for complete API docs.

## Cloudflare Deployment

```bash
cd ../../era-agent
make cf-build
docker tag era-agent:cloudflare your-registry/era-agent:latest
docker push your-registry/era-agent:latest
```

Then update `cloudflare/src/index.ts` with your registry and deploy.

## Troubleshooting

**Script won't run:**
```bash
chmod +x docker-compiler.sh
```

**Port conflict** - Edit `era-agent/docker-compose.yml`:
```yaml
ports:
  - "3000:8787"  # Use different port
```

**Build fails:**
```bash
docker system prune -a
cd ../../era-agent && ./build-docker.sh
```

**View logs:**
```bash
cd ../../era-agent && docker-compose logs -f
```

## Regenerating

Safe to re-run anytime:
```bash
./docker-compiler.sh
```

This updates all generated files in `era-agent/`. Your existing containers won't be affected until you rebuild.

## Templates

All Docker configuration is stored in `templates/`:
- `Dockerfile` - Multi-stage build configuration
- `docker-compose.yml` - Compose service definition
- `build-docker.sh` - Build helper script
- `test-docker.sh` - Test automation script
- `HTTP_API.md` - API documentation
- `DOCKER_DEPLOYMENT.md` - Deployment guide

To customize, edit files in `templates/` then re-run `./docker-compiler.sh`

