# ERA - Executable Runtime Agent

A Go-based VM orchestration system for running isolated code execution environments, deployed on Cloudflare Workers with container support.

## 📁 Project Structure

```
ERA-cf-clean/
├── era-agent/          # Go-based VM orchestration service
│   ├── agent           # Compiled binary
│   ├── ffi/            # Rust FFI layer
│   ├── Dockerfile      # Container image definition
│   ├── http_server.go  # HTTP API server
│   └── *.go            # Go source files
│
├── cloudflare/         # Cloudflare Worker deployment
│   ├── src/            # Worker TypeScript/JavaScript code
│   ├── wrangler.toml   # Cloudflare configuration
│   └── *.md            # Deployment documentation
│
├── wifski/             # Reference: Working Cloudflare container example
├── examples/           # Sample Python & JavaScript code
├── build-deploy.sh     # Automated build & deploy script
├── test-vm.sh          # Test script for VM execution
└── test-simple.sh      # Simple test with Python & Node.js examples
```

## 🎯 Architecture

### Separation of Concerns

This project maintains a **clean separation between the core service and deployment layer**:

**era-agent (Go)** - Core VM orchestration service
- Deployment-agnostic VM primitives
- VM lifecycle management (create, run, stop, clean)
- Multi-language support (Python 3.11, Node.js 20)
- HTTP API server
- Can run standalone: Docker, K8s, bare metal, or any cloud
- No knowledge of Cloudflare or deployment environment

**cloudflare (TypeScript Worker)** - Deployment & orchestration layer
- Routes requests to era-agent container
- Implements `/api/execute` convenience endpoint (orchestrates: create → run → cleanup)
- Durable Objects for state consistency
- Container configuration and deployment scripts
- Cloudflare-specific features (can add rate limiting, caching, etc.)
- No external registry needed (Cloudflare builds & hosts)

## 🚀 Quick Start

### Prerequisites
- **Docker Desktop** running locally
- **Node.js** 18+ installed
- **Go** 1.21+ (for building era-agent)
- **Cloudflare account** (free tier works)

### One-Command Deploy

```bash
# From ERA-cf-clean/ directory
./build-deploy.sh

# Or with options:
./build-deploy.sh --tail        # Deploy and tail logs
./build-deploy.sh --skip-go-build  # Skip Go build, use existing binary
```

### Manual Deploy

```bash
# 1. Build the Go agent
cd era-agent
make agent

# 2. Deploy to Cloudflare
cd ../cloudflare
npm install
npx wrangler login
npx wrangler deploy
```

**No Docker Hub needed!** Cloudflare builds from your Dockerfile and pushes to their registry automatically.

### Test Your Deployment

```bash
# Check health
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health

# Run the test script
./test-vm.sh https://era-agent.YOUR_SUBDOMAIN.workers.dev

# Test the simplified execute endpoint
./test-execute.sh https://era-agent.YOUR_SUBDOMAIN.workers.dev
```

## ⚡ Quick Execute API

The `/api/execute` endpoint provides a simplified way to run code without managing VM lifecycle. **This endpoint is implemented in the Cloudflare Worker layer** as an orchestration convenience - it calls the core VM API endpoints (create, run, delete) in sequence.

```bash
# Python
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/execute \
  -H "Content-Type: application/json" \
  -d '{
    "code": "print(2 + 2)",
    "language": "python",
    "timeout": 30
  }'

# JavaScript
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/execute \
  -H "Content-Type: application/json" \
  -d '{
    "code": "console.log(2 + 2)",
    "language": "javascript",
    "timeout": 30
  }'

# TypeScript
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/execute \
  -H "Content-Type: application/json" \
  -d '{
    "code": "const x: number = 2 + 2; console.log(x)",
    "language": "typescript",
    "timeout": 30
  }'
```

**Supported languages**: `python`, `py`, `javascript`, `js`, `node`, `nodejs`, `typescript`, `ts`

**What it does** (orchestrated by the Worker):
1. Creates a VM with the specified language
2. Encodes and runs your code
3. Automatically cleans up the VM
4. Returns the results

Perfect for one-off code execution! The Go agent remains deployment-agnostic and only provides core VM primitives.

## 🔄 Development Workflow

### Working on Go Code

```bash
cd era-agent

# Make changes to Go code
# ...

# Test locally first
make agent
./agent serve

# Test in another terminal
curl http://localhost:8787/health

# Deploy when ready
cd ..
./build-deploy.sh
```

### Working on Worker Code

```bash
cd cloudflare

# Make changes to src/index.ts
# ...

# Deploy (no need to rebuild Go if unchanged)
npx wrangler deploy
```

### Quick Redeploy

```bash
# From project root
./build-deploy.sh

# Or manually:
cd era-agent && make agent && cd ../cloudflare && npx wrangler deploy
```

## 🏗️ How It Works

1. **Build Go Agent**: `make agent` compiles the Go binary
2. **Docker Build**: Dockerfile packages the binary into a container
3. **Cloudflare Deploy**: `wrangler deploy` builds and pushes to CF's registry
4. **Worker Routing**: Worker forwards requests to the container

```
User Request
    ↓
Cloudflare Worker (cloudflare/src/)
    ↓
Container Binding (wrangler.toml)
    ↓
era-agent HTTP Server (http_server.go)
    ↓
VM Service (vm_service.go)
    ↓
Isolated Code Execution
```

## 🧪 Testing

### Test Locally

```bash
cd era-agent
./agent serve &

# Run the test script
cd ..
./test-vm.sh http://localhost:8787
```

### Test Production

```bash
# Set your worker URL
export WORKER_URL="https://era-agent.YOUR_SUBDOMAIN.workers.dev"

# Run test
./test-vm.sh $WORKER_URL

# Or manual test
curl $WORKER_URL/health
```

## 📚 API Endpoints

### Simplified Execution
- `POST /api/execute` - **Execute code directly (auto-creates & cleans up VM)**

### VM Management
- `GET /health` - Health check
- `POST /api/vm` - Create VM
- `GET /api/vm/{id}` - Get VM info
- `POST /api/vm/{id}/run` - Execute code in existing VM
- `POST /api/vm/{id}/stop` - Stop VM
- `DELETE /api/vm/{id}` - Delete VM
- `GET /api/vms` - List all VMs

See [HTTP_API.md](era-agent/HTTP_API.md) for complete API documentation.

## 📖 Documentation

- **[era-agent/README.md](era-agent/README.md)** - Agent service documentation
- **[cloudflare/README.md](cloudflare/README.md)** - Deployment guide
- **[cloudflare/DEPLOY.md](cloudflare/DEPLOY.md)** - Detailed deployment steps
- **[cloudflare/QUICK_REFERENCE.md](cloudflare/QUICK_REFERENCE.md)** - Quick commands
- **[examples/README.md](examples/README.md)** - Code examples in Python & JavaScript

## 🛠 Key Features

- **Multi-language Support**: Python 3.11, Node.js 20, and TypeScript
  - Python: Full standard library, data processing, classes
  - JavaScript: Modern ES6+, async/await, classes
  - TypeScript: Full type support via tsx
  - See [examples/](examples/) for code samples
- **Simplified Execute API**: Run code with a single API call (`/api/execute`)
- **Isolated Execution**: Each VM runs in a sandboxed environment
- **Resource Control**: Configurable CPU and memory
- **Network Policies**: Isolated or internet-enabled modes
- **State Management**: BoltDB for VM state persistence
- **HTTP API**: RESTful interface for all operations
- **Global Deployment**: Runs on Cloudflare's edge network

## 🎯 Use Cases

- Run untrusted code safely
- Execute user-submitted scripts
- API-based code execution service
- Multi-tenant code sandboxing
- Educational coding platforms
- CI/CD code testing

## 🤝 Contributing

When making changes:
1. Keep era-agent independent and testable
2. Update relevant documentation
3. Test locally before deploying to CF
4. Follow existing code patterns

## 📄 License

See LICENSE file in project root.
