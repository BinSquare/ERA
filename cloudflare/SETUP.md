# Session Setup System

The ERA Agent supports automatic package installation and environment configuration during session creation.

## Overview

When creating a session, you can provide a `setup` object that will:
1. Create a temporary VM with network access
2. Install specified packages (pip, npm, go modules)
3. Run custom setup commands
4. Extract all files to R2 storage
5. Make packages available in all future session runs

**⚡ Async Setup**: Package installation runs asynchronously to avoid Worker timeouts. The session is created immediately with `setup_status: "pending"`, and you can poll for completion.

## Usage

### Python (pip)

Install Python packages using pip:

```json
POST /api/sessions
{
  "language": "python",
  "persistent": true,
  "setup": {
    "pip": ["requests", "pandas", "numpy"]
  }
}
```

Or use a requirements.txt:

```json
{
  "setup": {
    "pip": {
      "requirements": "requests>=2.28.0\npandas==2.0.0\nnumpy"
    }
  }
}
```

### Node.js (npm)

Install npm packages:

```json
POST /api/sessions
{
  "language": "node",
  "persistent": true,
  "setup": {
    "npm": ["ms", "chalk", "axios"]
  }
}
```

**Note**: Large packages with many dependencies may timeout. Keep installations lightweight for best results.

**TypeScript Sessions**: npm package installation for TypeScript sessions currently has limitations due to module resolution issues with tsx. For TypeScript code, consider using:
- **Node.js sessions** with TypeScript transpilation
- **Deno sessions** with `npm:` imports (recommended for TypeScript)

### Go Modules

Install Go modules:

```json
POST /api/sessions
{
  "language": "go",
  "persistent": true,
  "setup": {
    "go": ["github.com/gin-gonic/gin"]
  }
}
```

### Custom Commands

Run arbitrary setup commands:

```json
POST /api/sessions
{
  "language": "python",
  "persistent": true,
  "setup": {
    "commands": [
      "mkdir -p /tmp/data",
      "wget https://example.com/data.csv -O /tmp/data/data.csv"
    ],
    "envs": {
      "SETUP_ENV": "production"
    }
  }
}
```

**⚠️ Security Warning:**
- The `envs` field provides environment variables ONLY during setup commands
- **Do NOT use for secrets** - they should be passed at runtime instead (see Security section below)
- Files like `.env`, `credentials.json`, etc. are automatically excluded from R2 storage

## Combined Setup

You can combine multiple setup types:

```json
{
  "setup": {
    "pip": ["requests"],
    "npm": ["ms"],
    "commands": ["mkdir -p /data"]
  }
}
```

## Response

### Initial Response

The API returns immediately with `setup_status: "pending"`:

```json
{
  "id": "my-session",
  "setup": {
    "pip": ["requests"]
  },
  "setup_status": "pending"
}
```

### Polling for Completion

Poll the session metadata to check setup status:

```bash
GET /api/sessions/{session_id}
```

Status values:
- `"pending"` - Setup hasn't started yet
- `"running"` - Setup is in progress
- `"completed"` - Setup finished successfully
- `"failed"` - Setup encountered an error

Once completed, the response includes `setup_result`:

```json
{
  "id": "my-session",
  "setup_status": "completed",
  "setup_result": {
    "success": true,
    "duration_ms": 5437,
    "pip_packages": ["requests"]
  }
}
```

If setup fails, the session creation will fail with error details:

```json
{
  "error": "Session setup failed",
  "id": "my-session",
  "setup_result": {
    "success": false,
    "error": "Pip install failed",
    "stderr": "...",
    "stdout": "..."
  }
}
```

## Limitations

1. **Setup Duration**: Packages with many files may take several minutes to extract to R2 storage
   - **File count is the bottleneck**, not package size
   - Examples:
     - `lodash`: 1,054 files, ~1.4 MB → 3-5 minutes (works, but slow)
     - `ai` (Vercel AI SDK): ~3 MB → May take 2-4 minutes depending on file count
     - Most packages: < 500 files → Under 1 minute
   - Container runtime limit: ~5-7 minutes total

2. **Async Only**: Setup runs asynchronously - you must poll for completion before running code

3. **Network**: Setup VMs have full network access; runtime VMs are isolated

4. **Persistence**: Only works with `persistent: true` sessions

### Recommendations for Large Packages

**For packages with 500+ files or that timeout:**

1. **Use Deno with `npm:` imports** (recommended)
   - No setup needed - packages download on-demand
   - Example: `import { z } from "npm:zod@3.22.0"`
   - Works great for TypeScript projects

2. **Use modular alternatives**
   - Instead of `lodash` → use `lodash-es` or specific functions like `lodash.chunk`
   - Instead of full frameworks → use lightweight alternatives

3. **Accept the one-time cost**
   - Remember: Setup is a one-time 5-minute cost
   - All subsequent runs are instant (packages loaded from R2)
   - Great for production sessions that run for days/weeks

## Architecture

The setup system uses a plugin architecture:

- `src/plugins/types.ts` - Type definitions
- `src/plugins/package_managers.ts` - Package installation functions
- `src/plugins/session_setup.ts` - Setup orchestration

Setup happens once at session creation, then all installed packages persist across runs via R2 storage.

## Security

### Environment Variables

**⚠️ IMPORTANT: Do NOT store secrets in setup `envs`**

The `envs` field in setup is only for non-sensitive configuration during package installation. For runtime secrets, pass them with each `/run` request.

```json
// ❌ BAD - Don't do this!
{
  "setup": {
    "envs": {
      "API_KEY": "secret123",
      "DATABASE_PASSWORD": "password"
    }
  }
}

// ✅ GOOD - Pass secrets at runtime
POST /api/sessions/{session_id}/run
{
  "code": "import os; print(os.environ['API_KEY'])",
  "env": {
    "API_KEY": "secret123"
  }
}
```

### Sensitive File Exclusion

The setup system **automatically excludes** these sensitive files from R2 storage:

- `.env`, `.env.local`, `.env.production`, `.env.development`
- `credentials.json`, `service-account.json`
- `.aws/credentials`
- `.ssh/id_rsa`, `.ssh/id_ed25519`
- `.netrc`, `.dockercfg`
- `.npmrc`, `.pypirc`
- `secrets.json`, `secrets.yaml`, `secrets.yml`

Even if your setup commands create these files, they will NOT be persisted to R2.

### Best Practices

1. **Use setup `envs` only for non-sensitive config**
   ```json
   {
     "setup": {
       "envs": {
         "NODE_ENV": "production",
         "LOG_LEVEL": "info"
       }
     }
   }
   ```

2. **Pass secrets at runtime**
   ```bash
   curl -X POST https://anewera.dev/api/sessions/my-session/run \
     -H "Content-Type: application/json" \
     -d '{
       "code": "print(os.environ.get(\"API_KEY\"))",
       "env": {"API_KEY": "secret123"}
     }'
   ```

3. **Secrets are never persisted**
   - Runtime `env` vars exist only for that single execution
   - They are NOT saved to R2
   - Each run must provide secrets again
