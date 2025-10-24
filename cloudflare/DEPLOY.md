# ERA Agent - Cloudflare Containers Deployment Guide

## ✅ No Docker Hub Needed!

**Great news!** Cloudflare Containers has its **own built-in registry**. You don't need Docker Hub, GitHub Container Registry, or any external registry!

When you run `wrangler deploy`, it automatically:
1. Builds your Docker image locally
2. Pushes to **Cloudflare's registry** (automatically)
3. Deploys your Worker

---

## 🚀 Quick Deployment Steps

### 1. Prerequisites

**Required:**
- **Docker Desktop** running locally
- **Node.js** 18+ installed
- **Cloudflare account** (free tier works!)

**Check Docker is running:**
```bash
docker info
# Should show Docker info, not error
```

### 2. Install Dependencies

```bash
cd cloudflare
npm install
```

### 3. Login to Cloudflare

```bash
npx wrangler login
```

This opens your browser to authenticate.

### 4. Deploy!

```bash
npx wrangler deploy
```

That's it! Wrangler will:
- ✅ Build `../era-agent/Dockerfile` using your local Docker
- ✅ Push to Cloudflare's container registry (automatic)
- ✅ Deploy your Worker with container binding
- ✅ Give you a live URL

**Expected time:**
- First deploy: 3-5 minutes
- Subsequent deploys: 1-3 minutes (Docker layer caching)

---

## 🔧 What's in wrangler.toml?

```toml
name = "era-agent"
main = "src/index.ts"
compatibility_date = "2024-10-01"

# Container configuration
[[containers]]
name = "era-agent-container"
class_name = "EraAgent"
image = "../era-agent/Dockerfile"      # ← Just point to your Dockerfile!
instance_type = "standard"
max_instances = 10

# Durable Object binding
[[durable_objects.bindings]]
name = "ERA_AGENT"
class_name = "EraAgent"

# Environment variables
[vars]
AGENT_LOG_LEVEL = "info"
```

**Key point:** `image = "../era-agent/Dockerfile"` tells Cloudflare where your Dockerfile is. It builds and pushes everything automatically!

---

## 🧪 Testing Your Deployment

```bash
# Get your worker URL from wrangler output, then:

# Health check
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health

# Create a VM
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/vm \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu_count":1,"memory_mib":256}'

# View logs
npx wrangler tail
```

---

## 🔄 Making Updates

### After Changing Go Code

```bash
# 1. Rebuild the Go binary
cd ../era-agent
make agent

# 2. Redeploy (Cloudflare rebuilds Docker automatically)
cd ../cloudflare
npx wrangler deploy
```

### After Changing Worker Code (src/index.ts)

```bash
# Just redeploy - no Docker rebuild needed
npx wrangler deploy
```

### After Changing Dockerfile

```bash
# Just redeploy - Cloudflare rebuilds from new Dockerfile
npx wrangler deploy
```

---

## 🎯 Using the Automated Build Script

For even easier deployment, use the root-level script:

```bash
# From ERA-cf-clean/ directory
./build-deploy.sh

# This does everything:
# 1. Checks prerequisites
# 2. Builds Go agent
# 3. Validates Docker build
# 4. Deploys to Cloudflare
# 5. Shows you the URL

# Options:
./build-deploy.sh --tail             # Tail logs after deploy
./build-deploy.sh --skip-go-build    # Use existing binary
./build-deploy.sh --help             # Show all options
```

---

## 📊 How It Works

### The Build Process

```
Your Code               Cloudflare
────────                ──────────

1. Edit Go code
   ↓
2. Build binary
   (make agent)
   ↓
3. wrangler deploy ───> Builds Docker locally
                        ↓
                        Pushes to CF registry
                        ↓
                        Deploys Worker
                        ↓
                        Live! 🎉
```

### What Gets Built?

1. **Go binary**: Compiled with `make agent` in `../era-agent/`
2. **Docker image**: Built from `../era-agent/Dockerfile`
   - Includes Go binary
   - Includes runtime dependencies
   - Based on lightweight Linux image
3. **Worker**: TypeScript code in `src/index.ts`
   - Routes requests to container
   - Manages Durable Object state

---

## 🆘 Troubleshooting

### "Docker is not running"

**Error:**
```
Cannot connect to the Docker daemon
```

**Solution:**
1. Open Docker Desktop
2. Wait for it to start
3. Verify: `docker info`
4. Try again: `npx wrangler deploy`

---

### "Build failed"

**Error:**
```
Error building Docker image
```

**Solution:**
1. Test locally: `cd ../era-agent && docker build -t test .`
2. Check if `agent` binary exists: `ls -la ../era-agent/agent`
3. If not, build it: `cd ../era-agent && make agent`
4. Try again

---

### "Deployment timed out"

**Normal behavior:** First deploys can take 3-5 minutes.

**If it's stuck:**
1. Check your internet connection
2. Check Cloudflare status: https://www.cloudflarestatus.com/
3. Cancel (Ctrl+C) and try again

---

### "Container not responding"

**Solution:**
1. Check logs: `npx wrangler tail`
2. Look for startup errors
3. Test Go server locally:
   ```bash
   cd ../era-agent
   ./agent serve
   curl http://localhost:8787/health
   ```
4. If local works, redeploy: `npx wrangler deploy`

---

### "Permission denied"

**Error:**
```
Permission denied while trying to connect to Docker daemon
```

**Solution (Linux):**
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

**Solution (Mac/Windows):**
- Ensure Docker Desktop is running
- Check Docker Desktop settings → Resources

---

## 📚 Advanced Topics

### Optimizing Docker Build

**Multi-stage builds** (already used in Dockerfile):
```dockerfile
# Build stage
FROM golang:1.21 AS builder
# ... build Go binary

# Runtime stage
FROM alpine:latest
# ... copy binary only
```

**Benefits:**
- Smaller final image
- Faster deploys
- Less bandwidth

### Reducing Go Binary Size

```bash
# In era-agent/Makefile
go build -ldflags="-s -w" -o agent .

# -s: Strip debug symbols
# -w: Strip DWARF debug info
```

Can reduce binary from ~20MB to ~10MB.

### Custom Build Tags

```toml
# wrangler.toml
[vars]
BUILD_VERSION = "v1.2.3"
BUILD_DATE = "2024-10-23"
```

Access in Go:
```go
version := os.Getenv("BUILD_VERSION")
```

---

## 🎓 Key Concepts

### 1. Cloudflare's Built-in Registry

- No need to push to Docker Hub manually
- Wrangler handles everything
- Private to your account
- Automatic versioning

### 2. Durable Objects

- Ensures state consistency
- All requests go to same instance
- BoltDB state persists
- Can scale to multiple instances later

### 3. Container Bindings

- Connects Worker to Container
- Defined in `wrangler.toml`
- Accessed via `env.ERA_AGENT`
- HTTP proxy to container

---

## 🔗 Additional Resources

### Cloudflare Docs
- [Container Workers Guide](https://developers.cloudflare.com/workers/runtime-apis/bindings/service-bindings/container-workers/)
- [Durable Objects Guide](https://developers.cloudflare.com/durable-objects/)
- [Wrangler CLI Reference](https://developers.cloudflare.com/workers/wrangler/)

### Your Project
- [Main README](../README.md)
- [Cloudflare README](README.md)
- [Go Agent README](../era-agent/README.md)

---

## ✅ Deployment Checklist

Before deploying:
- [ ] Docker Desktop is running
- [ ] Go binary is built (`era-agent/agent` exists)
- [ ] Dependencies installed (`npm install`)
- [ ] Logged in to Cloudflare (`npx wrangler login`)
- [ ] Dockerfile is correct
- [ ] Local test passed (`./agent serve` works)

Deploy:
- [ ] Run `npx wrangler deploy`
- [ ] Wait 3-5 minutes
- [ ] Test health endpoint
- [ ] Check logs with `npx wrangler tail`

---

## 🎉 Success!

If everything worked:
```
✨  Built successfully
✨  Uploaded successfully
✨  Deployed successfully
```

Your ERA Agent is now live on Cloudflare's global network!

**Next steps:**
1. Test the API endpoints
2. Monitor with `npx wrangler tail`
3. Make changes and redeploy
4. Share your deployment!

---

**Questions?** Check the [main README](../README.md) or [Cloudflare docs](https://developers.cloudflare.com/workers/).
