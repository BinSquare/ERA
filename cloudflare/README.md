# ERA Agent - Cloudflare Deployment

> 🎉 **Cloudflare Containers is now stable!** (as of late 2024)

## 📦 Docker Configuration

Docker files are managed by the **Cloudflare Docker Compiler** in `scripts/cloudflare-docker/`. 

- **Templates** are stored in `scripts/cloudflare-docker/templates/`
- **Generated files** go to `era-agent/` when you run the compiler
- **Keep era-agent clean** - generated files are temporary

See `scripts/cloudflare-docker/README.md` for details.

## ✨ NEW: Automatic Package Installation

**Install packages automatically when creating a session - works with ALL languages!**

### Supported Package Managers

| Language | Package Manager | Example |
|----------|----------------|---------|
| **Python** | pip | `"setup": {"pip": ["requests", "pandas"]}` |
| **Node.js** | npm | `"setup": {"npm": ["axios", "express"]}` |
| **TypeScript** | npm | `"setup": {"npm": ["ms", "chalk"]}` |
| **Go** | go modules | `"setup": {"go": ["github.com/gin-gonic/gin"]}` |
| **Deno** | npm: imports | No setup needed - use `import { x } from "npm:package"` |

### Quick Example

```bash
# Create Python session with packages
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "persistent": true,
    "setup": {
      "pip": ["requests", "pandas", "numpy"]
    }
  }'

# Returns immediately with setup_status: "pending"
# Poll for completion, then run code with installed packages!
```

### Why This Is Awesome 🚀

- ✅ **Async setup** - No Worker timeout limits
- ✅ **Install once, use forever** - Packages persist via R2 storage
- ✅ **All languages supported** - Python, Node.js, TypeScript, Go, Deno
- ✅ **Custom commands** - Run setup scripts, download files, etc.

### ⚠️ Large Packages

Packages with **many files** (500+) may take several minutes to set up:
- `lodash` (1,054 files): ~3-5 minutes - **works, just slow**
- `ai` (Vercel AI SDK): ~2-4 minutes depending on dependencies
- Most packages: < 1 minute

**The bottleneck is file count, not size.** Setup is a one-time cost - subsequent runs are instant!

**For large packages**, consider using **Deno with `npm:` imports** (no setup needed).

**→ See [SETUP.md](./SETUP.md) for complete documentation**
**→ Run tests: `./tests/test-setup.sh`**

---

## 📋 Overview

This directory contains the Cloudflare Worker that routes requests to your containerized Go agent.

### Architecture

```
User Request
    ↓
Cloudflare Worker (src/index.ts)
    ↓
Container Binding: env.ERA_AGENT
    ↓
Your Go HTTP Server (port 8787)
    ↓
VMService → Create/Run/Manage VMs
```

## 🚀 Quick Start

### Prerequisites

1. **Cloudflare Account** (free tier works!)
2. **Docker Desktop** running locally
3. **Node.js** 18+ installed
4. **Your Go agent** built in `../era-agent/`

**No Docker Hub or external registry needed!** Cloudflare builds and hosts everything automatically.

### Quick Deploy

**Option 1: Use the automated script (recommended)**

```bash
./build-and-deploy.sh
```

This script:
1. Generates Docker files from templates
2. Builds the Docker image
3. Deploys to Cloudflare
4. Offers to clean up generated files

**Option 2: Manual steps**

```bash
# 1. Generate Docker configuration
cd ../scripts/cloudflare-docker
./docker-compiler.sh

# 2. Build Docker image
cd ../../era-agent
docker build -t era-agent:latest .

# 3. Install dependencies
cd ../cloudflare
npm install

# 4. Login to Cloudflare
npx wrangler login

# 5. Create R2 bucket for session storage
npx wrangler r2 bucket create era-sessions

# 6. Deploy
npx wrangler deploy
```

That's it! 🎉

## 📦 Package Installation (Setup System)

One of the most powerful features of ERA Agent is **automatic package installation**. Instead of manually installing dependencies in each execution, you can specify packages during session creation and they'll be installed once and persist forever!

### Quick Examples

#### Python with pip

```bash
# Create session with Python packages
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "session_id": "ml-analysis",
    "persistent": true,
    "setup": {
      "pip": ["requests", "pandas", "numpy", "scikit-learn"]
    }
  }'

# Returns immediately: {"id": "ml-analysis", "setup_status": "pending"}

# Wait ~10-30 seconds, then check status
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/ml-analysis
# → "setup_status": "completed"

# Now run code with all packages available!
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/ml-analysis/run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import pandas as pd\nimport numpy as np\nprint(f\"pandas {pd.__version__}\")\nprint(f\"numpy {np.__version__}\")"
  }'
```

#### Node.js with npm

```bash
# Create session with npm packages
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "node",
    "session_id": "web-scraper",
    "persistent": true,
    "setup": {
      "npm": ["axios", "cheerio", "moment"]
    }
  }'

# Wait for setup to complete
# Then use the packages!
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/web-scraper/run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "const axios = require(\"axios\");\nconst moment = require(\"moment\");\nconsole.log(\"axios ready!\");\nconsole.log(\"Date:\", moment().format(\"YYYY-MM-DD\"));"
  }'
```

#### TypeScript with npm

```bash
# TypeScript sessions use Node.js + npm packages
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "typescript",
    "session_id": "ts-app",
    "persistent": true,
    "setup": {
      "npm": ["ms", "chalk"]
    }
  }'

# Run TypeScript code with tsx
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/ts-app/run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import ms from \"ms\";\nconst duration = ms(\"2 days\");\nconsole.log(\"2 days:\", duration);"
  }'
```

**Note:** TypeScript has some module resolution limitations with tsx. For best TypeScript support, use **Deno** with npm: imports.

#### Go with go modules

```bash
# Install Go modules
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "go",
    "session_id": "go-api",
    "persistent": true,
    "setup": {
      "go": ["github.com/gin-gonic/gin@v1.9.1"]
    }
  }'

# Run Go code with installed modules
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/go-api/run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "package main\nimport \"fmt\"\nfunc main() { fmt.Println(\"Go modules loaded!\") }"
  }'
```

#### Deno with npm: imports (No setup needed!)

```bash
# Deno downloads packages on-demand via npm: imports
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"language": "deno", "session_id": "deno-app"}'

# Use npm: imports directly - no setup required!
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/deno-app/run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import { format } from \"npm:date-fns@3.0.0\";\nconsole.log(format(new Date(), \"yyyy-MM-dd\"));"
  }'
```

#### Combined Setup

```bash
# Install packages AND run custom commands
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "persistent": true,
    "setup": {
      "pip": ["requests"],
      "commands": [
        "mkdir -p /tmp/data",
        "curl -o /tmp/data/sample.json https://api.example.com/data"
      ]
    }
  }'
```

### How It Works

1. **Async Setup**: Package installation runs in the background using `ctx.waitUntil()`
2. **No Timeout Limits**: Unlike synchronous setup, async setup can take as long as needed (within Container limits)
3. **Persistent Storage**: Installed packages are saved to R2 and injected into every session run
4. **Poll for Completion**: Use `GET /api/sessions/{id}` to check `setup_status`

### Status Values

- `"pending"` → Setup queued, hasn't started yet
- `"running"` → Setup in progress (installing packages)
- `"completed"` → Setup finished successfully ✅
- `"failed"` → Setup encountered an error ❌

**Full documentation:** [SETUP.md](./SETUP.md)
**Test script:** `./tests/test-setup.sh`

## 🔧 What Happens During Deploy?

### Full Workflow

When you run `./build-and-deploy.sh`:

1. **Generates Docker Files**
   - Runs `scripts/cloudflare-docker/docker-compiler.sh`
   - Copies templates to `era-agent/` directory
   - Creates: Dockerfile, docker-compose.yml, helper scripts

2. **Builds Docker Image**
   - Uses `era-agent/Dockerfile` to build locally
   - Multi-stage build: Go compilation → Runtime environment
   - Includes Python, Node.js, Deno, Go compilers

3. **Deploys to Cloudflare**
   - Reads `wrangler.toml` (points to `../era-agent/Dockerfile`)
   - Pushes image to Cloudflare's registry (automatic)
   - Creates/updates Worker with container binding
   - Configures R2 storage and Durable Objects

4. **Cleanup (Optional)**
   - Removes generated Docker files from `era-agent/`
   - Keeps `era-agent/` directory clean

5. **Ready!**
   - Your API is live at `https://era-agent.YOUR_SUBDOMAIN.workers.dev`

### Using wrangler deploy directly

If you already have Docker files in `era-agent/`:

```bash
npx wrangler deploy
```

Cloudflare will:
- Build from existing `../era-agent/Dockerfile`
- Push to their registry automatically
- Deploy the Worker

## 📁 File Structure

```
cloudflare/
├── src/
│   └── index.ts        # Worker entry point (routes to container)
├── wrangler.toml       # Configuration (points to ../era-agent/Dockerfile)
├── package.json        # Dependencies
└── README.md           # This file
```

## 🔧 Configuration

### wrangler.toml Explained

```toml
name = "era-agent"              # Your worker name
main = "src/index.ts"           # Worker entry point
compatibility_date = "2024-10-01"

# Container configuration
[[containers]]
name = "era-agent-container"
class_name = "EraAgent"
image = "../era-agent/Dockerfile"    # ← Points to your Dockerfile
instance_type = "standard"
max_instances = 10

# Durable Object bindings
[[durable_objects.bindings]]
name = "ERA_AGENT"                   # ← Container binding
class_name = "EraAgent"

[[durable_objects.bindings]]
name = "SESSIONS"                    # ← Session management
class_name = "SessionDO"

# R2 bucket for session file storage
[[r2_buckets]]
binding = "SESSIONS_BUCKET"
bucket_name = "era-sessions"         # ← Create with: wrangler r2 bucket create era-sessions

# Migrations (required for Durable Objects)
[[migrations]]
tag = "v1"
new_sqlite_classes = ["EraAgent"]

[[migrations]]
tag = "v2"
new_sqlite_classes = ["SessionDO"]

# Environment variables (passed to your container)
[vars]
AGENT_LOG_LEVEL = "info"
```

### How the Worker Connects to Your Container

```typescript
// src/index.ts
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Get a Durable Object instance (ensures consistent state)
    const durableObjectId = env.ERA_AGENT.idFromName("primary");
    const stub = env.ERA_AGENT.get(durableObjectId);

    // Forward request to your Go container
    return await stub.fetch(request);
  }
}
```

**Key points:**
- `ERA_AGENT` binding connects to your container
- Using Durable Objects ensures state consistency (BoltDB in container)
- All requests go to the same container instance (for now)

## 📦 Session Management

The ERA Agent supports multiple execution modes for different use cases:

| Feature | Ephemeral | Session (Ephemeral Data) | Session (Persistent Files + Data) |
|---------|-----------|-------------------------|----------------------------------|
| **Endpoint** | `/api/execute` | `/api/sessions` | `/api/sessions` |
| **Lifecycle** | One-shot | Until deleted | Until deleted |
| **VM** | Created & destroyed | New VM per run | New VM per run |
| **Data Persistence** | ❌ | ✅ DO storage | ✅ DO storage |
| **File Persistence** | ❌ | ❌ | ✅ R2 storage |
| **Custom IDs** | ❌ | ✅ | ✅ |
| **List/Duplicate** | ❌ | ✅ | ✅ |
| **Best For** | Quick scripts | Stateful apps | Data pipelines |

### Two Execution Modes

#### 1. Ephemeral Execution (One-shot)

Simple, stateless code execution:

```bash
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/execute \
  -H "Content-Type: application/json" \
  -d '{
    "code": "print(\"Hello World\")",
    "language": "python"
  }'
```

- **Use case**: Quick scripts, data processing, one-time calculations
- **Lifecycle**: VM created → code runs → VM destroyed
- **Files**: Not persisted

#### 2. Persistent Sessions

Long-running workflows with file storage:

```bash
# Create a session
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "persistent": true
  }'

# Returns: {"id": "sess_...", ...}

# Run code in session (files are persisted)
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/sess_.../run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "with open(\"data.txt\", \"w\") as f: f.write(\"persistent data\")"
  }'

# Run more code - files from previous run are available
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/sess_.../run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "with open(\"data.txt\", \"r\") as f: print(f.read())"
  }'
```

- **Use case**: Data analysis pipelines, stateful workflows, incremental processing
- **Lifecycle**: Session persists until deleted, new VM per execution
- **Files**: Persisted in R2, injected/extracted automatically
- **Storage**: Metadata in Durable Objects, files in R2 bucket

### Session Management Patterns

#### Custom Session IDs ("Coming Back" to Sessions)

Instead of auto-generated IDs, use **memorable custom IDs** to easily return to your sessions:

```bash
# Create session with custom ID
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "id": "my-counter",           # Custom ID instead of auto-generated
    "language": "python",
    "persistent": false,
    "data": {"count": 0}
  }'

# Come back to it anytime using the same ID
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/my-counter/run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import json\nwith open(\".session_data.json\") as f: data = json.load(f)\ndata[\"count\"] += 1\nwith open(\".session_data.json\", \"w\") as f: json.dump(data, f)\nprint(\"Count:\", data[\"count\"])"
  }'

# Get current state
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/my-counter
```

**Custom ID Rules:**
- Allowed characters: `a-z`, `A-Z`, `0-9`, `-`, `_`
- Examples: `my-counter`, `user-123-cart`, `data_analysis_v2`
- Must be unique (409 error if ID already exists)

**Use Cases:**
- **Per-user sessions**: `user-${userId}-cart`, `user-${userId}-workspace`
- **Named workflows**: `daily-report`, `data-pipeline-prod`
- **Version tracking**: `experiment-v1`, `experiment-v2`
- **Easy debugging**: `test-counter`, `debug-session`

#### List All Sessions

```bash
GET /api/sessions

# Returns:
{
  "sessions": [
    {
      "id": "my-counter",
      "language": "python",
      "created_at": "2025-10-23T21:43:15.479Z"
    },
    {
      "id": "shopping-cart",
      "language": "python",
      "created_at": "2025-10-23T21:46:07.289Z"
    }
  ],
  "count": 2
}
```

**Use this to:**
- See all active sessions
- Find sessions you created earlier
- Monitor session creation across your app

#### Duplicate Session

Clone a session with all its data and files:

```bash
POST /api/sessions/{id}/duplicate
Content-Type: application/json

{
  "id": "new-session-name"  # Optional, auto-generates if not provided
}

# Example: Create backup of counter
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/my-counter/duplicate \
  -H "Content-Type: application/json" \
  -d '{"id": "my-counter-backup"}'

# Result: New session with copied data
{
  "id": "my-counter-backup",
  "created_at": "2025-10-23T21:47:20.123Z",  # New timestamp
  "data": {
    "count": 15  # Copied from original
  },
  ...
}
```

**What gets copied:**
- ✅ Session data (`.session_data.json`)
- ✅ All files (if `persistent: true`)
- ✅ Language, metadata settings
- ❌ Run history (`last_run_at` resets)

**Use Cases:**
- **Backups**: Save state before risky operations
- **Templates**: Create base session, duplicate for each user
- **Testing**: Clone production state for debugging
- **Branching**: Try different approaches from same starting point

```bash
# Example: Template pattern
# 1. Create template with initial state
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "id": "cart-template",
    "language": "python",
    "data": {"cart": [], "total": 0, "tax_rate": 0.08}
  }'

# 2. Duplicate for each user
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/cart-template/duplicate \
  -H "Content-Type: application/json" \
  -d '{"id": "user-123-cart"}'

curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/cart-template/duplicate \
  -H "Content-Type: application/json" \
  -d '{"id": "user-456-cart"}'

# Each user now has independent cart with same initial state
```

#### Delete Session

```bash
DELETE /api/sessions/{id}

# Example
curl -X DELETE https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/my-counter

# Returns:
{
  "deleted": "my-counter"
}
```

**What gets deleted:**
- ✅ All files in R2
- ✅ Session metadata in Durable Objects
- ✅ Registry entry (removes from list)

### Session API Endpoints

#### Create Session

```bash
POST /api/sessions
Content-Type: application/json

{
  "id": "my-session",       # Optional custom ID (auto-generated if omitted)
  "language": "python",      # python, node, typescript
  "persistent": true,        # Enable file persistence (R2)
  "metadata": {             # Optional metadata
    "project": "analysis",
    "user": "jane"
  },
  "data": {                 # Optional lightweight data (Durable Objects)
    "count": 0,
    "settings": {}
  }
}

# Response:
{
  "id": "my-session",  # Or auto-generated like "sess_1761254854924_nhxv0a57k"
  "created_at": "2025-10-23T21:24:26.901Z",
  "last_run_at": "",
  "language": "python",
  "persistent": true,
  "file_count": 0,
  "total_size_bytes": 0,
  "metadata": { ... },
  "data": {
    "count": 0,
    "settings": {}
  }
}
```

#### Run Code in Session

```bash
POST /api/sessions/{session_id}/run
Content-Type: application/json

{
  "code": "print('Hello from session')",
  "timeout": 30              # Optional, default 30s
}

# Response:
{
  "exit_code": 0,
  "stdout": "Hello from session\n",
  "stderr": "",
  "duration": "15.31525ms",
  "session_id": "sess_...",
  "data": {                   # Updated session data (if modified)
    "count": 5
  }
}
```

#### List Files in Session

```bash
GET /api/sessions/{session_id}/files

# Response:
{
  "files": [
    {
      "path": "data.json",
      "size": 16,
      "uploaded": "2025-10-23T21:27:42.895Z"
    },
    {
      "path": "myfile.txt",
      "size": 15,
      "uploaded": "2025-10-23T21:27:43.786Z"
    }
  ],
  "count": 2
}
```

#### Download File from Session

```bash
GET /api/sessions/{session_id}/files/{file_path}

# Example:
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/sess_.../files/data.json

# Returns file content with appropriate Content-Type header
```

#### Upload File to Session

```bash
PUT /api/sessions/{session_id}/files/{file_path}
Content-Type: application/octet-stream

# Example:
curl -X PUT https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/sess_.../files/config.json \
  -H "Content-Type: application/json" \
  -d '{"setting": "value"}'

# Response:
{
  "path": "config.json",
  "size": 20
}
```

#### Get Session Metadata

```bash
GET /api/sessions/{session_id}

# Returns complete session metadata including data
```

#### List All Sessions

```bash
GET /api/sessions

# Returns array of all session summaries
```

#### Duplicate Session

```bash
POST /api/sessions/{session_id}/duplicate
Content-Type: application/json

{
  "id": "new-session-id"  # Optional
}

# Creates copy with all data and files
```

#### Delete Session

```bash
DELETE /api/sessions/{session_id}

# Deletes all files from R2, session metadata, and registry entry
```

### File Persistence Architecture

```
Session Flow (Persistent):

1. POST /api/sessions/{id}/run
   ↓
2. Create temporary VM
   ↓
3. INJECT: Download files from R2 → Upload to VM
   ↓
4. Execute code in VM (files available)
   ↓
5. EXTRACT: Download files from VM → Upload to R2
   ↓
6. Cleanup VM (files preserved in R2)
   ↓
7. Return execution results
```

**Storage:**
- **Durable Objects**: Session metadata, timestamps, file counts (<128KB)
- **R2 Bucket**: Actual file contents (unlimited storage)
- **Pattern**: Inject/Extract files around ephemeral VM executions

### Lightweight Data Persistence

In addition to file storage, sessions support **lightweight data persistence** for structured data like counters, configuration, or simple state. This data is stored directly in Durable Objects (fast, no file system overhead).

#### How It Works

- **`.session_data.json` file**: Automatically injected before code runs, extracted after
- **Stored in Durable Objects**: Fast access, no R2 required
- **Language-agnostic**: Works with Python, Node, TypeScript
- **Returned in API response**: See updated `data` field immediately

#### Example 1: Counter

```bash
# Create session with initial counter
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"language": "python", "persistent": false, "data": {"count": 0}}'

# Increment counter
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/sess_.../run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import json\nwith open(\".session_data.json\") as f:\n  data = json.load(f)\ndata[\"count\"] += 5\nwith open(\".session_data.json\", \"w\") as f:\n  json.dump(data, f)\nprint(\"Counter:\", data[\"count\"])"
  }'

# Response includes updated data:
{
  "exit_code": 0,
  "stdout": "Counter: 5\n",
  "data": {
    "count": 5
  }
}

# Run again - counter persists
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/sess_.../run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import json\nwith open(\".session_data.json\") as f:\n  data = json.load(f)\ndata[\"count\"] += 3\nwith open(\".session_data.json\", \"w\") as f:\n  json.dump(data, f)\nprint(\"Counter:\", data[\"count\"])"
  }'

# Response: Counter: 8
```

#### Example 2: Shopping Cart

```bash
# Create session with empty cart
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"language": "python", "persistent": false, "data": {"cart": [], "total": 0}}'

# Add items
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/sess_.../run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import json\n\nwith open(\".session_data.json\") as f:\n  data = json.load(f)\n\nitem = {\"name\": \"Apple\", \"price\": 1.50, \"qty\": 3}\ndata[\"cart\"].append(item)\ndata[\"total\"] += item[\"price\"] * item[\"qty\"]\n\nwith open(\".session_data.json\", \"w\") as f:\n  json.dump(data, f)\n\nprint(\"Cart total: $%.2f\" % data[\"total\"])"
  }'

# Response:
{
  "exit_code": 0,
  "stdout": "Cart total: $4.50\n",
  "data": {
    "cart": [{"name": "Apple", "price": 1.5, "qty": 3}],
    "total": 4.5
  }
}

# Add more items - cart accumulates
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/sess_.../run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import json\n\nwith open(\".session_data.json\") as f:\n  data = json.load(f)\n\nitem = {\"name\": \"Banana\", \"price\": 0.75, \"qty\": 5}\ndata[\"cart\"].append(item)\ndata[\"total\"] += item[\"price\"] * item[\"qty\"]\n\nwith open(\".session_data.json\", \"w\") as f:\n  json.dump(data, f)\n\nprint(\"Cart has\", len(data[\"cart\"]), \"items\")\nprint(\"Cart total: $%.2f\" % data[\"total\"])"
  }'

# Response: Cart has 2 items, Cart total: $8.25
```

#### File Persistence vs Data Persistence

| Feature | File Persistence | Data Persistence |
|---------|-----------------|------------------|
| **Storage** | R2 Bucket | Durable Objects |
| **Best for** | Large files, binary data | Small structured data (<128KB) |
| **Access** | File API endpoints | Automatic `.session_data.json` |
| **Overhead** | R2 read/write latency | In-memory, instant |
| **Use case** | Datasets, images, documents | Counters, config, state |

You can use both together! Files for heavy data, `.session_data.json` for lightweight state.

### Example: Data Analysis Workflow

```bash
# 1. Create session
SESSION_ID=$(curl -sf -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"language":"python","persistent":true}' | jq -r '.id')

# 2. Upload dataset
curl -X PUT https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/$SESSION_ID/files/data.csv \
  --data-binary @dataset.csv

# 3. Run analysis
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/$SESSION_ID/run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import pandas as pd\ndf = pd.read_csv(\"data.csv\")\ndf.describe().to_json(\"stats.json\")"
  }'

# 4. Download results
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/$SESSION_ID/files/stats.json

# 5. Run more analysis (stats.json is still available)
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/$SESSION_ID/run \
  -H "Content-Type: application/json" \
  -d '{
    "code": "import json\nwith open(\"stats.json\") as f: print(json.load(f))"
  }'

# 6. Cleanup
curl -X DELETE https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/sessions/$SESSION_ID
```

## 🧪 Testing

### Test Locally (if supported)

```bash
# Note: Local container testing may be limited
npx wrangler dev
```

### Test Against Production

```bash
# Health check
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health

# Create a VM
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/vm \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu_count":1,"memory_mib":256}'

# Get VM info (use ID from above)
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/vm/python-123456789
```

## 📊 Monitoring

### View Live Logs

```bash
# Tail logs in real-time
npx wrangler tail

# Or view in dashboard:
# https://dash.cloudflare.com → Workers & Pages → era-agent → Logs
```

### Check Status

```bash
# Worker info
npx wrangler whoami

# Health check
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health
```

## 🔄 Updating Your Deployment

### After Changing Go Code

```bash
# Rebuild and redeploy
cd cloudflare
./build-and-deploy.sh
```

Or manually:
```bash
cd era-agent
make agent
cd ../cloudflare
npx wrangler deploy
```

### After Changing Worker Code

```bash
# Just redeploy (no Docker rebuild needed)
cd cloudflare
npx wrangler deploy
```

### After Changing Docker Templates

```bash
# Regenerate Docker files and redeploy
cd scripts/cloudflare-docker
./docker-compiler.sh

cd ../../cloudflare
./build-and-deploy.sh
```

## 🎯 Using the Automated Script

Use the Cloudflare build-and-deploy script:

```bash
cd cloudflare
./build-and-deploy.sh
```

This script:
- Generates Docker files from templates
- Builds the Docker image locally  
- Deploys to Cloudflare
- Checks for R2 bucket and creates if needed
- Offers to clean up generated Docker files

**Interactive prompts:**
- Cloudflare login (if not logged in)
- Clean up generated files (after deploy)

## ⚙️ Advanced Configuration

### Adjusting Container Resources

Edit `wrangler.toml`:

```toml
[[containers]]
instance_type = "standard"    # or "standard-2", "standard-4"
max_instances = 10              # Max concurrent instances
```

### Container Sleep Settings

Edit `src/index.ts`:

```typescript
export class EraAgent extends Container {
  defaultPort = 8787;
  sleepAfter = '5m';    // Stop after 5 min inactivity
                        // Options: '30s', '5m', '1h', '2h'
}
```

**Trade-off:**
- Shorter sleep = lower cost, possible cold starts
- Longer sleep = faster response, higher cost

### Custom Domain

Add to `wrangler.toml`:

```toml
routes = [
  { pattern = "api.yourdomain.com", zone_name = "yourdomain.com" }
]
```

### Environment Variables

Add to `wrangler.toml`:

```toml
[vars]
AGENT_LOG_LEVEL = "debug"
CUSTOM_VAR = "value"
```

These are passed to your Go container.

## 🆘 Troubleshooting

### "Container binding not found"

**Solution:**
1. Check `wrangler.toml` has correct binding configuration
2. Ensure `[[containers]]` and `[[durable_objects.bindings]]` sections exist
3. Redeploy: `npx wrangler deploy`

### "Docker build failed"

**Solution:**
1. Verify Docker Desktop is running: `docker info`
2. Test build locally: `cd ../era-agent && docker build -t test .`
3. Check Dockerfile for errors
4. Ensure `agent` binary exists in `../era-agent/`

### "Deployment takes too long"

**Normal behavior:**
- First deploy: 2-5 minutes (building Docker image)
- Subsequent deploys: 1-3 minutes (layer caching)

**Speed up:**
- Optimize Dockerfile (use multi-stage builds)
- Reduce binary size (`go build -ldflags="-s -w"`)

### "Container not responding"

**Solution:**
1. Check logs: `npx wrangler tail`
2. Verify Go server starts on port 8787
3. Test locally: `cd ../era-agent && ./agent serve`
4. Check `/health` endpoint responds

### "Cannot connect to Durable Object"

**Solution:**
1. Verify migration ran: check `wrangler.toml` has `[[migrations]]`
2. Delete and redeploy if needed
3. Check Durable Object name matches in binding

## 📚 Resources

### Cloudflare Docs
- [Workers Overview](https://developers.cloudflare.com/workers/)
- [Container Workers](https://developers.cloudflare.com/workers/runtime-apis/bindings/service-bindings/container-workers/)
- [Durable Objects](https://developers.cloudflare.com/durable-objects/)

### Your Project
- [Go Agent README](../era-agent/README.md)
- [HTTP API Docs](../era-agent/HTTP_API.md)
- [Project README](../README.md)

### Community
- [Cloudflare Discord](https://discord.gg/cloudflaredev)
- [Cloudflare Community Forum](https://community.cloudflare.com/)

## 💡 Best Practices

1. **Test Locally First**: Always test Go agent locally before deploying
2. **Use Version Tags**: Track deployments with comments in wrangler.toml
3. **Monitor Logs**: Keep `wrangler tail` running during testing
4. **Check Docker Size**: Smaller images deploy faster
5. **Optimize Binary**: Use build flags to reduce size
6. **Handle Errors**: Log errors in both Worker and Container

## 🎯 Quick Commands Reference

```bash
# Generate Docker files
cd scripts/cloudflare-docker && ./docker-compiler.sh

# Build and deploy (all-in-one)
cd cloudflare && ./build-and-deploy.sh

# Deploy only (if Docker files already exist)
cd cloudflare && npx wrangler deploy

# View logs
npx wrangler tail

# Check login
npx wrangler whoami

# Get worker info
npx wrangler deployments list

# Delete deployment
npx wrangler delete

# Test health endpoint
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health

# Clean up generated Docker files
cd era-agent && rm -f Dockerfile docker-compose.yml .dockerignore *.sh HTTP_API.md DOCKER_DEPLOYMENT.md
```

## 🔒 Security Notes

- Container runs in Cloudflare's secure sandbox
- No internet access by default (network isolation)
- State is per-Durable-Object (isolated)
- Environment variables are encrypted

---

## Summary

**What you need to know:**

1. **No Docker Hub needed** - Cloudflare builds and hosts everything
2. **One command to deploy** - `npx wrangler deploy` does it all
3. **Points to Dockerfile** - `wrangler.toml` references `../era-agent/Dockerfile`
4. **Automatic build & push** - Cloudflare handles the Docker build and registry
5. **Live in minutes** - First deploy ~3-5 min, updates ~1-2 min

**Workflow:**
```
Edit Go code → Build binary → wrangler deploy → Test
```

Ready to deploy! 🚀
