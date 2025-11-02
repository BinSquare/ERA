# ERA - ERA of Runtime for Agents

Securely run any code, in any language, with no repercussions.

ERA is an open-source project providing fast and secure runtime environments with persistent storage for running your AI-agents. Want to self-host? Get started with our documentation.

## 🎥 Demo Video

A demo video showing how to install and use the CLI tool is available in the [era-agent directory](era-agent/README.md). This video covers:

- Installing dependencies and compiling the CLI tool
- Creating and accessing local VMs
- Running code and agents through commands or scripts
- Uploading and downloading files to/from a VM

## 📁 Project Structure

```
ERA/
├── era-agent/          # Go-based VM orchestration service
│   ├── agent           # Compiled binary
│   ├── api_server.go   # HTTP API server
│   └── *.go            # Go source files
│
├── cloudflare/         # Cloudflare Worker deployment
│   ├── src/            # Worker TypeScript/JavaScript code
│   ├── wrangler.toml   # Cloudflare configuration
│   └── README.md       # Deployment documentation
│
├── docs/               # Additional documentation
├── examples/           # Sample Python & JavaScript code
├── recipes/            # Ready-to-run code examples
├── tests/              # Test scripts
└── skill-layer/        # Skill-based agent system
```

## 🎯 Architecture

This project maintains a **clean separation between the core service and deployment layer**:

**era-agent (Go)** - Core VM orchestration service

- Deployment-agnostic VM primitives
- VM lifecycle management (create, run, stop, clean)
- Multi-language support (Python, Node.js, TypeScript, Go, Deno)
- HTTP API server
- Can run standalone: Docker, K8s, bare metal, or any cloud

**cloudflare (TypeScript Worker)** - Deployment & orchestration layer

- Routes requests to era-agent container
- Session management with Durable Objects
- File persistence via R2 storage
- Automatic package installation
- No external registry needed (Cloudflare builds & hosts)

## 🚀 Quick Start

### Prerequisites

- **Cloudflare account** (free tier works)
- **Node.js** 18+ installed
- **Docker Desktop** (for local development)
- **Go** 1.21+ (optional, for building era-agent locally)

### Deploy to Cloudflare

```bash
# 1. Build the Go agent
cd era-agent
make agent

# 2. Deploy to Cloudflare
cd ../cloudflare
npm install
npx wrangler login
npx wrangler r2 bucket create era-sessions
npx wrangler deploy
```

**No Docker Hub needed!** Cloudflare builds from your Dockerfile and pushes to their registry automatically.

See [cloudflare/README.md](cloudflare/README.md) for detailed deployment instructions.

### Quick Test

```bash
# Health check
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health

# Execute code
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/execute \
  -H "Content-Type: application/json" \
  -d '{"code": "print(2 + 2)", "language": "python"}'
```

## 🔄 Development Workflow

**Local Development:**

- Test the Go agent locally: See [era-agent/README.md](era-agent/README.md)
- Test the Worker locally: `cd cloudflare && npx wrangler dev`

**Deployment:**

- Update Go code: Rebuild with `make agent`, then redeploy Worker
- Update Worker code: Just run `npx wrangler deploy`

See [cloudflare/README.md](cloudflare/README.md) for full development workflow.

## 📚 API Overview

### Execution Endpoints

- `POST /api/execute` - Execute code directly (ephemeral, auto-cleanup)
- `POST /api/sessions` - Create persistent session
- `POST /api/sessions/{id}/run` - Run code in session

### Session Management

- `GET /api/sessions` - List all sessions
- `GET /api/sessions/{id}` - Get session details
- `GET /api/sessions/{id}/files` - List session files
- `DELETE /api/sessions/{id}` - Delete session

### Health & VM Management

- `GET /health` - Health check
- `POST /api/vm` - Create VM (low-level)
- `GET /api/vms` - List all VMs

For complete API documentation, see:

- [cloudflare/README.md](cloudflare/README.md) - Session API & examples
- [era-agent/README.md](era-agent/README.md) - VM management & CLI
- [docs/QUICKSTART_HTTP.md](docs/QUICKSTART_HTTP.md) - HTTP server guide

## 📖 Documentation

- **[era-agent/README.md](era-agent/README.md)** - Go agent CLI & local development
- **[cloudflare/README.md](cloudflare/README.md)** - Cloudflare deployment & session API
- **[cloudflare/SETUP.md](cloudflare/SETUP.md)** - Package installation system
- **[examples/README.md](examples/README.md)** - Code examples (Python & JavaScript)
- **[recipes/README.md](recipes/README.md)** - Ready-to-run recipe examples
- **[docs/](docs/)** - Additional guides (MCP, recipes, storage, etc.)

## 🛠 Key Features

- **Multi-language Support**: Python, Node.js, TypeScript, Go, Deno
  - Full standard libraries and modern language features
  - See [examples/](examples/) for code samples
- **Automatic Package Installation**: Install npm/pip packages automatically on session creation
  - Async setup with status polling
  - Packages persist via R2 storage
  - See [cloudflare/SETUP.md](cloudflare/SETUP.md) for details
- **Persistent Sessions**: Long-running workflows with file and data persistence
  - File storage via R2 bucket
  - Lightweight data storage in Durable Objects
  - Custom session IDs for easy management
- **Isolated Execution**: Each VM runs in a sandboxed environment
- **Global Deployment**: Runs on Cloudflare's edge network
- **HTTP API**: RESTful interface for all operations

## 🎯 Use Cases

- **API-based code execution**: Run user-submitted scripts safely
- **Data processing pipelines**: Persistent sessions for multi-step workflows
- **Educational platforms**: Sandboxed code execution for learners
- **CI/CD testing**: Execute test suites in isolated environments
- **AI/LLM integrations**: Run code generated by AI models safely
- **Webhooks & callbacks**: Execute code triggered by external events
- **Multi-tenant sandboxing**: Isolated execution for multiple users

## 🤝 Contributing

When making changes:

1. Keep era-agent independent and testable
2. Update relevant documentation
3. Test locally before deploying to Cloudflare
4. Follow existing code patterns

For more details, see the documentation in each subdirectory.

## 📄 License

See LICENSE file in project root.
