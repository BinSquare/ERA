# Docker Setup for Cloudflare Deployment

## Overview

Docker configuration is managed by the **Cloudflare Docker Compiler** tool located at `scripts/cloudflare-docker/`.

## Quick Start

### One-Command Deploy

```bash
./build-and-deploy.sh
```

This script handles everything:
1. Generates Docker files from templates
2. Builds the Docker image
3. Deploys to Cloudflare
4. Offers cleanup of temporary files

### Manual Steps

If you prefer manual control:

```bash
# 1. Generate Docker files
cd ../scripts/cloudflare-docker
./docker-compiler.sh

# 2. Build image
cd ../../era-agent
docker build -t era-agent:latest .

# 3. Deploy
cd ../cloudflare
npx wrangler deploy

# 4. (Optional) Clean up
cd ../era-agent
rm -f Dockerfile docker-compose.yml .dockerignore build-docker.sh test-docker.sh HTTP_API.md DOCKER_DEPLOYMENT.md
```

## File Organization

```
ERA/
├── scripts/cloudflare-docker/
│   ├── docker-compiler.sh          # Generator tool
│   └── templates/                  # Source templates
│       ├── Dockerfile
│       ├── docker-compose.yml
│       ├── .dockerignore
│       └── ... (docs and scripts)
│
├── era-agent/
│   ├── *.go                        # Go source (permanent)
│   └── Dockerfile                  # Generated (temporary)
│
└── cloudflare/
    ├── build-and-deploy.sh         # All-in-one deployment
    ├── deploy.sh                   # Alternative deploy script
    └── wrangler.toml               # Points to ../era-agent/Dockerfile
```

## Why This Structure?

- **Templates in plugin/**: Single source of truth for Docker config
- **Generated in era-agent/**: Temporary files for building
- **Keep era-agent clean**: Generated files can be deleted after deploy
- **Flexible**: Edit templates, regenerate anytime

## Customizing Docker Configuration

1. Edit templates in `scripts/cloudflare-docker/templates/`
2. Run `./docker-compiler.sh` to regenerate
3. Build and deploy

## Common Tasks

### Update Docker Configuration

```bash
# Edit templates
vim ../scripts/cloudflare-docker/templates/Dockerfile

# Regenerate and deploy
./build-and-deploy.sh
```

### Deploy Without Regenerating

If Docker files already exist in `era-agent/`:

```bash
npx wrangler deploy
```

### Clean Up Generated Files

```bash
cd ../era-agent
rm -f Dockerfile docker-compose.yml .dockerignore build-docker.sh test-docker.sh HTTP_API.md DOCKER_DEPLOYMENT.md
```

Or answer "yes" when `build-and-deploy.sh` asks.

## Troubleshooting

### "Dockerfile not found"

Run the generator:
```bash
cd ../scripts/cloudflare-docker
./docker-compiler.sh
```

### Docker build fails

Check Docker is running:
```bash
docker info
```

Test build locally:
```bash
cd ../era-agent
docker build -t era-agent:test .
```

### Want to modify templates

All Docker templates are in:
```
scripts/cloudflare-docker/templates/
```

Edit there, then regenerate.

## Documentation

- **Tool README**: `scripts/cloudflare-docker/README.md`
- **Deployment Guide**: `cloudflare/README.md`
- **Root Docker Guide**: `DOCKER.md`

## Quick Reference

```bash
# Generate Docker files
cd scripts/cloudflare-docker && ./docker-compiler.sh

# Build and deploy
cd cloudflare && ./build-and-deploy.sh

# Deploy only
cd cloudflare && npx wrangler deploy

# Clean up
cd era-agent && rm -f Dockerfile docker-compose.yml .dockerignore *.sh *.md
```
