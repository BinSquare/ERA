# ERA Agent - Quick Reference

> **TL;DR**: No Docker Hub needed. Just run `npx wrangler deploy`!

## 🚀 Essential Commands

### Initial Setup (One Time)

```bash
# Install dependencies
cd cloudflare
npm install

# Login to Cloudflare
npx wrangler login
```

### Deploy

```bash
# Simple deploy (from cloudflare/ directory)
npx wrangler deploy

# Or use automated script (from ERA-cf-clean/ directory)
./build-deploy.sh
```

That's it! Cloudflare builds and deploys everything automatically.

---

## 📝 Common Workflows

### Make Changes to Go Code

```bash
# 1. Edit Go files in era-agent/
# 2. Rebuild binary
cd era-agent
make agent

# 3. Deploy
cd ../cloudflare
npx wrangler deploy
```

### Make Changes to Worker Code

```bash
# 1. Edit src/index.ts
# 2. Deploy (no Go rebuild needed)
npx wrangler deploy
```

### Full Rebuild & Deploy

```bash
# From project root
./build-deploy.sh
```

---

## 🔧 Monitoring & Debugging

```bash
# Tail logs in real-time
npx wrangler tail

# Check who's logged in
npx wrangler whoami

# List deployments
npx wrangler deployments list

# Check worker status
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health
```

---

## 🧪 Testing Endpoints

```bash
# Set your worker URL
export WORKER_URL="https://era-agent.YOUR_SUBDOMAIN.workers.dev"

# Health check
curl $WORKER_URL/health

# Create a Python VM
curl -X POST $WORKER_URL/api/vm \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "cpu_count": 1,
    "memory_mib": 256
  }'

# Get VM info (replace with your VM ID)
curl $WORKER_URL/api/vm/python-1234567890

# Run code in VM
curl -X POST $WORKER_URL/api/vm/python-1234567890/run \
  -H "Content-Type: application/json" \
  -d '{
    "command": "python -c \"print(42)\"",
    "timeout": 30
  }'

# Stop VM
curl -X POST $WORKER_URL/api/vm/python-1234567890/stop

# Delete VM
curl -X DELETE $WORKER_URL/api/vm/python-1234567890

# List all VMs
curl $WORKER_URL/api/vms
```

---

## 📂 Key Files

```
ERA-cf-clean/
├── build-deploy.sh              # Automated build & deploy script
├── era-agent/
│   ├── Dockerfile               # Container definition
│   ├── agent                    # Compiled Go binary
│   ├── Makefile                 # Build commands
│   └── *.go                     # Go source code
└── cloudflare/
    ├── wrangler.toml            # CF configuration
    ├── src/index.ts             # Worker code
    └── package.json             # Dependencies
```

---

## 🔗 Configuration

### wrangler.toml

```toml
name = "era-agent"                   # Worker name
main = "src/index.ts"                # Entry point
image = "../era-agent/Dockerfile"    # Your Dockerfile

[vars]
AGENT_LOG_LEVEL = "info"             # Environment variable
```

### Container Settings (src/index.ts)

```typescript
export class EraAgent extends Container {
  defaultPort = 8787;      // Go server port
  sleepAfter = '5m';       // Inactivity timeout
}
```

---

## ⚡ Quick Troubleshooting

| Issue | Solution |
|-------|----------|
| Docker not running | Open Docker Desktop, run `docker info` |
| Deploy fails | Check logs with `npx wrangler tail` |
| Binary missing | Run `cd era-agent && make agent` |
| Container timeout | Test locally: `cd era-agent && ./agent serve` |
| Auth expired | Run `npx wrangler login` again |

---

## 🎯 Build-Deploy Script Options

```bash
# Full build and deploy
./build-deploy.sh

# Skip Go build (use existing binary)
./build-deploy.sh --skip-go-build

# Deploy and tail logs
./build-deploy.sh --tail

# Build only, don't deploy
./build-deploy.sh --skip-deploy

# Show help
./build-deploy.sh --help
```

---

## 📊 What Happens During Deploy?

```
Local Machine                Cloudflare
─────────────                ──────────

wrangler deploy ──────────▶ Reads wrangler.toml
                            ▼
                            Builds Docker image locally
                            ▼
                            Pushes to CF registry (auto)
                            ▼
                            Deploys Worker
                            ▼
                            ✅ Live!
```

**Time:** 3-5 minutes first deploy, 1-3 minutes after (caching)

---

## 🌐 URLs & Endpoints

**Worker URL:**
```
https://era-agent.YOUR_SUBDOMAIN.workers.dev
```

**Endpoints:**
- `GET /health` - Health check
- `POST /api/vm` - Create VM
- `GET /api/vm/{id}` - Get VM info
- `POST /api/vm/{id}/run` - Execute code
- `POST /api/vm/{id}/stop` - Stop VM
- `DELETE /api/vm/{id}` - Delete VM
- `GET /api/vms` - List all VMs

---

## 💡 Pro Tips

1. **Always test locally first**: `cd era-agent && ./agent serve`
2. **Use the build script**: Saves time and checks everything
3. **Watch logs during testing**: `npx wrangler tail` in a separate terminal
4. **Docker caching speeds up deploys**: Don't rebuild if code unchanged
5. **Health check first**: Before running tests, verify `/health` responds

---

## 🔗 More Info

- **Full deployment guide**: [DEPLOY.md](DEPLOY.md)
- **Detailed README**: [README.md](README.md)
- **Project overview**: [../README.md](../README.md)
- **Go agent docs**: [../era-agent/README.md](../era-agent/README.md)

---

## 📋 Deployment Checklist

Before deploying:
- [ ] Docker Desktop is running
- [ ] Go agent built: `cd era-agent && make agent`
- [ ] Dependencies installed: `npm install`
- [ ] Logged in: `npx wrangler login`

Deploy:
- [ ] Run: `npx wrangler deploy`
- [ ] Wait 3-5 minutes
- [ ] Test: `curl https://YOUR-WORKER.workers.dev/health`
- [ ] Monitor: `npx wrangler tail`

---

**Remember**: No Docker Hub, no manual pushes. Just `npx wrangler deploy`! 🚀
