# ERA - Executable Runtime Agent

> **Welcome to the ERA of Runtime for Agents**  
> Securely run any code, in any language, with no repercussions.

ERA is an open-source project providing fast and secure runtime environments with persistent storage for running your AI-agents.

## What is ERA?

ERA gives your AI agents the ability to safely execute code in isolated sandboxes. Whether you're building:

- 🤖 AI agents that need to run user-submitted code
- 🔄 Workflow automation with dynamic script execution
- 🧪 Multi-language testing environments
- 🐳 Container-free code execution platforms

ERA provides secure, fast, and persistent execution environments that work across Python, JavaScript, TypeScript, and more.

## ✨ Key Features

- **🔒 Secure Execution** - Each code run happens in an isolated VM sandbox
- **🌐 Multi-Language** - Python, JavaScript, TypeScript, Node.js, Go, and Deno
- **💾 Persistent Storage** - Files and data persist across executions
- **🚀 Quick API** - Simple REST API or MCP (Model Context Protocol) integration
- **☁️ Self-Hostable** - Deploy on Cloudflare, Docker, K8s, or bare metal
- **📦 Package Management** - Automatic dependency installation (pip, npm, go modules)
- **🔄 Stateful Sessions** - Maintain state across multiple code executions
- **🌍 Public URLs** - Make your code accessible via webhooks and callbacks

## 🚀 Quick Start

### Option 1: Self-Host on Cloudflare (Recommended)

Deploy ERA in minutes to Cloudflare Workers:

```bash
# Prerequisites
# - Node.js 18+
# - Docker Desktop
# - Cloudflare account (free tier works!)

# 1. Install dependencies
cd cloudflare
npm install

# 2. Login to Cloudflare
npx wrangler login

# 3. Create R2 bucket for session storage
npx wrangler r2 bucket create era-sessions

# 4. Deploy!
npx wrangler deploy
```

That's it! Your ERA instance is live at `https://era-agent.YOUR_SUBDOMAIN.workers.dev`

### Option 2: Local Development (Go CLI)

Run ERA locally for development:

```bash
# Prerequisites
# - Go 1.21+
# - Docker Desktop

# 1. Build the agent
cd era-agent
make agent

# 2. Run locally
./agent serve

# 3. Test it
curl http://localhost:8787/health
```

## 📝 Usage Examples

### Simple Code Execution

Execute code with a single API call:

```bash
# Python
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/execute \
  -H "Content-Type: application/json" \
  -d '{
    "code": "print(2 + 2)",
    "language": "python",
    "timeout": 30
  }'
```

### Persistent Sessions

Create a session to maintain state across executions:

```bash
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "persistent": true
  }'
```

Run code in your session:

```bash
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/my-session/run \
  -H "Content-Type: application/json" \
  -d '{"code": "print(\"Hello from ERA!\")"}'
```

### Install Packages Once, Use Forever

Create a session with dependencies that persist:

```bash
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "persistent": true,
    "setup": {
      "pip": ["pandas", "numpy", "requests"]
    }
  }'
```

Wait for setup to complete, then use your packages in every execution!

## 🎯 Use Cases

- **AI Agents** - Let your AI execute code to solve problems dynamically
- **Code Execution Services** - Build platforms like CodePen or Repl.it
- **Educational Platforms** - Create safe coding environments for learners
- **CI/CD Testing** - Run tests across multiple languages and environments
- **Data Processing** - Build pipelines with persistent storage and dependencies
- **Webhook Handlers** - Receive and process webhooks with custom logic
- **Sandboxed Environments** - Run untrusted code safely in production

## 🏗️ Architecture

ERA maintains a clean separation between core service and deployment:

```
┌─────────────────────────────────────────────┐
│         Cloudflare Worker                   │
│  (Session Management, API Routes)           │
└─────────────────┬───────────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────────┐
│      Container Binding                      │
│  (Durable Object to Go Container)           │
└─────────────────┬───────────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────────┐
│         era-agent (Go)                      │
│  (VM Orchestration, Execution)              │
└─────────────────┬───────────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────────┐
│      Isolated VM Execution                  │
│  (Python, Node, TypeScript, etc.)          │
└─────────────────────────────────────────────┘
```

**Key Components:**

- **era-agent (Go)** - Core VM orchestration, deployment-agnostic
- **Cloudflare Worker** - Session management, persistent storage (R2, DO)
- **Container Runtime** - Isolated execution environments

## 📚 Documentation

- **[Cloudflare Deployment](cloudflare/README.md)** - Deploy to Cloudflare Workers
- **[Local Development](era-agent/README.md)** - Run ERA locally
- **[API Reference](docs/QUICKSTART_HTTP.md)** - HTTP API documentation
- **[MCP Integration](docs/MCP_SETUP.md)** - Model Context Protocol setup
- **[Examples](examples/README.md)** - Code samples and recipes
- **[Storage Proxy](docs/STORAGE_PROXY.md)** - Access Cloudflare storage from code

## 🤝 Contributing

We welcome contributions! When making changes:

1. Test locally before deploying
2. Keep era-agent deployment-agnostic
3. Update relevant documentation
4. Follow existing code patterns

## 🌐 Learn More

- 🌐 **Website**: [anewera.dev](https://anewera.dev)
- 📖 **Full Documentation**: [Docs](https://anewera.dev/docs)
- 🚀 **Quick Start**: [Cloudflare Deployment](cloudflare/README.md)
- 🔧 **Self-Host Guide**: [Local Setup](era-agent/README.md)

## 📄 License

See LICENSE file in project root.

---

**Ready to build something amazing?** Start with our [quick start guide](https://anewera.dev/docs) or deploy instantly to [Cloudflare](cloudflare/README.md).
