# Docker Deployment Guide for ERA Agent

This guide covers deploying the ERA Agent using Docker, both locally and on Cloudflare Containers.

## Prerequisites

- Docker 20.10+ or Docker Desktop
- Docker Compose 1.29+ (optional, for docker-compose deployment)
- For Cloudflare: A Cloudflare account with Containers enabled

## Quick Start

### Local Development

```bash
# Build the Docker image
make docker-build

# Run with Docker Compose
make docker-up

# View logs
make docker-logs

# Stop the service
make docker-down
```

Or manually:

```bash
# Build
docker build -t era-agent:latest .

# Run
docker run -d \
  --name era-agent \
  -p 8787:8787 \
  -v era-agent-state:/var/lib/agent \
  era-agent:latest

# Test
curl http://localhost:8787/health

# Stop
docker stop era-agent
docker rm era-agent
```

## Configuration

### Environment Variables

Set these in `docker-compose.yml` or pass with `-e` flag:

```yaml
environment:
  - AGENT_MODE=http
  - PORT=8787
  - AGENT_LOG_LEVEL=info
  - AGENT_STATE_DIR=/var/lib/agent
  - ERA_API_KEY=your-secret-key  # Optional: Enable authentication
```

### Volumes

The agent uses a persistent volume for VM state:

```yaml
volumes:
  - agent-state:/var/lib/agent
```

## Cloudflare Containers Deployment

### Step 1: Build and Push Image

```bash
# Build for Cloudflare
docker build -t era-agent:cloudflare .

# Tag for your registry
docker tag era-agent:cloudflare your-registry.com/era-agent:latest

# Push to registry
docker push your-registry.com/era-agent:latest
```

### Step 2: Update Cloudflare Worker

In `cloudflare/src/index.ts`:

```typescript
import { Container } from "@cloudflare/workers-container";

export class Backend extends Container {
  image = "your-registry.com/era-agent:latest";
  defaultPort = 8787;
  sleepAfter = "2h";
  
  // Optional: Add environment variables
  env = {
    AGENT_LOG_LEVEL: "info",
    ERA_API_KEY: "your-secret-key"
  };
}

export default {
  async fetch(request, env) {
    const backend = new Backend();
    return backend.fetch(request);
  }
};
```

### Step 3: Deploy to Cloudflare

```bash
cd cloudflare
npm install
npm run deploy
```

## Architecture

The Docker image includes:

- **Go binary**: The ERA Agent compiled for Linux
- **Python 3.11**: For Python code execution
- **Node.js 20.x**: For JavaScript/TypeScript execution
- **Deno**: For Deno/TypeScript execution
- **Go compiler**: For Go code execution

## VM Runtime in Docker

The new ERA Agent uses `krunvm` for VM management on macOS/Linux hosts. However, in Docker containers (including Cloudflare), it uses a simpler runtime approach:

- **Processes are isolated** using container features
- **Resource limits** are enforced via cgroups
- **Network isolation** is handled by Docker networking
- **State persistence** via mounted volumes

This provides similar isolation guarantees while being compatible with container environments.

## Security Considerations

1. **API Authentication**: Set `ERA_API_KEY` in production
2. **Network Isolation**: VMs default to `network: none`
3. **Resource Limits**: Configure CPU and memory limits per VM
4. **User Isolation**: Container runs as non-root user (UID 1000)

## Monitoring

### Health Checks

Docker includes a built-in health check:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8787/health
```

Check health status:

```bash
docker inspect era-agent --format='{{.State.Health.Status}}'
```

### Logs

```bash
# Docker logs
docker logs -f era-agent

# Docker Compose logs
docker-compose logs -f
```

## Troubleshooting

### Container won't start

```bash
# Check logs
docker logs era-agent

# Check if port is in use
lsof -i :8787

# Try a different port
docker run -p 3000:8787 era-agent:latest
```

### VM operations fail

```bash
# Check state directory
docker exec era-agent ls -la /var/lib/agent

# Check logs with debug level
docker run -e AGENT_LOG_LEVEL=debug era-agent:latest
```

### Out of disk space

```bash
# Clean up old images
docker system prune -a

# Remove unused volumes
docker volume prune
```

## Performance Tips

1. **Use volumes for state**: Mounted volumes are faster than container layers
2. **Set appropriate resource limits**: Don't over-allocate CPU/memory
3. **Enable buildkit**: `DOCKER_BUILDKIT=1 docker build ...`
4. **Multi-stage builds**: Already optimized in the Dockerfile

## Next Steps

- Set up monitoring (Prometheus/Grafana)
- Configure automatic backups of state volume
- Set up CI/CD pipeline for automated builds
- Add load balancing for multiple instances

