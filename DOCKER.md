# Docker Deployment for ERA Agent

Quick guide to deploying ERA Agent with Docker for Cloudflare Containers.

## Generate Docker Files

```bash
cd scripts/cloudflare-docker
./docker-compiler.sh
```

This copies templates to `era-agent/`:
- `Dockerfile`
- `docker-compose.yml`  
- Helper scripts and documentation

## Build and Run

```bash
cd era-agent

# Build
./build-docker.sh

# Run
docker-compose up -d

# Test
curl http://localhost:8787/health
```

## API Example

```bash
# Run Python code
curl -X POST http://localhost:8787/api/vm/temp \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "command": "python -c \"print(42)\"",
    "timeout": 30
  }'
```

## Cloudflare Deployment

```bash
cd era-agent
make cf-build
docker tag era-agent:cloudflare your-registry/era-agent:latest
docker push your-registry/era-agent:latest

# Update cloudflare/src/index.ts with registry URL
cd ../cloudflare
npm run deploy
```

## Documentation

After running the compiler:

- **API Reference**: `era-agent/HTTP_API.md`
- **Deployment Guide**: `era-agent/DOCKER_DEPLOYMENT.md`
- **Tool Docs**: `scripts/cloudflare-docker/README.md`

## Make Targets

```bash
make docker-build    # Build image
make docker-up       # Start
make docker-logs     # View logs
make docker-down     # Stop
make cf-build        # Cloudflare build
```

## Regenerate

Safe to re-run anytime:

```bash
cd scripts/cloudflare-docker
./docker-compiler.sh
```
