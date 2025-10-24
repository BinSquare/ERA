# ERA Agent HTTP API

The ERA Agent can run as an HTTP server, exposing a REST API for VM management. This is ideal for Cloudflare Containers, Docker deployments, or any cloud environment.

## Running the HTTP Server

### Method 1: Using the `serve` command
```bash
./agent serve
```

### Method 2: Using environment variable
```bash
AGENT_MODE=http ./agent
```

### Method 3: Custom port
```bash
PORT=3000 ./agent serve
```

## API Endpoints

Base URL: `http://localhost:8787`

### Health Check
```bash
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "time": "2025-10-23T12:34:56Z"
}
```

---

### Execute Code (Simplified) - NOT IMPLEMENTED IN GO AGENT

> **Note**: The `/api/execute` endpoint is **not part of the Go agent**. It's implemented in the Cloudflare Worker layer (see `cloudflare/src/index.ts`) as an orchestration convenience that calls the core VM endpoints below (create → run → cleanup).
>
> The Go agent remains deployment-agnostic and only provides the primitive VM operations below. This separation allows the agent to be deployed anywhere (Docker, K8s, other clouds) while deployment-specific conveniences like `/api/execute` can be added at the orchestration layer.

If you're using the Cloudflare deployment, you can use:
- `POST /api/execute` - Simplified execution (Worker orchestrates VM lifecycle)

Otherwise, use the core VM operations below to manage VMs explicitly.

---

### Create VM
```bash
POST /api/vm
Content-Type: application/json

{
  "language": "python",
  "cpu_count": 2,
  "memory_mib": 512,
  "network_mode": "none",
  "persist": false
}
```

**Response:**
```json
{
  "id": "python-1729692845123456789",
  "language": "python",
  "rootfs_image": "agent/python:3.11-20251023",
  "cpu_count": 2,
  "memory_mib": 512,
  "network_mode": "none",
  "persist": false,
  "status": "running",
  "created_at": "2025-10-23T12:34:05Z",
  "last_run_at": "0001-01-01T00:00:00Z"
}
```

---

### Get VM Details
```bash
GET /api/vm/{id}
```

**Example:**
```bash
curl http://localhost:8787/api/vm/python-1729692845123456789
```

**Response:**
```json
{
  "id": "python-1729692845123456789",
  "language": "python",
  "rootfs_image": "agent/python:3.11-20251023",
  "cpu_count": 2,
  "memory_mib": 512,
  "network_mode": "none",
  "persist": false,
  "status": "running",
  "created_at": "2025-10-23T12:34:05Z",
  "last_run_at": "2025-10-23T12:35:00Z"
}
```

---

### Run Code in VM
```bash
POST /api/vm/{id}/run
Content-Type: application/json

{
  "command": "python /workspace/in/hello.py",
  "timeout": 30,
  "file": "/path/to/local/hello.py"
}
```

**Example:**
```bash
curl -X POST http://localhost:8787/api/vm/python-1729692845123456789/run \
  -H "Content-Type: application/json" \
  -d '{
    "command": "python -c \"print('Hello from VM!')\"",
    "timeout": 30
  }'
```

**Response:**
```json
{
  "exit_code": 0,
  "stdout": "executed: python -c \"print('Hello from VM!')\"\n",
  "stderr": "",
  "duration": "1.234s"
}
```

**Note:** The `file` parameter is optional and should be a local path on the server.

---

### Stop VM
```bash
POST /api/vm/{id}/stop
```

**Example:**
```bash
curl -X POST http://localhost:8787/api/vm/python-1729692845123456789/stop
```

**Response:**
```json
{
  "status": "stopped",
  "vm_id": "python-1729692845123456789",
  "message": "VM stopped successfully"
}
```

---

### Delete/Clean VM
```bash
DELETE /api/vm/{id}?keep_persist=false
```

**Example:**
```bash
curl -X DELETE http://localhost:8787/api/vm/python-1729692845123456789
```

**Response:**
```json
{
  "status": "deleted",
  "vm_id": "python-1729692845123456789",
  "message": "VM cleaned successfully"
}
```

**Query Parameters:**
- `keep_persist=true` - Retain persistent volume (default: false)

---

### List All VMs
```bash
GET /api/vms
```

**Example:**
```bash
curl http://localhost:8787/api/vms
```

**Response:**
```json
{
  "vms": [
    {
      "id": "python-1729692845123456789",
      "language": "python",
      "status": "running",
      "cpu_count": 2,
      "memory_mib": 512,
      "created_at": "2025-10-23T12:34:05Z"
    },
    {
      "id": "node-1729692845987654321",
      "language": "node",
      "status": "stopped",
      "cpu_count": 1,
      "memory_mib": 256,
      "created_at": "2025-10-23T12:30:00Z"
    }
  ],
  "count": 2
}
```

---

## Complete Example Workflow

### 1. Start the server
```bash
./agent serve
```

### 2. Create a Python VM
```bash
curl -X POST http://localhost:8787/api/vm \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "cpu_count": 1,
    "memory_mib": 256,
    "network_mode": "none"
  }'
```

**Save the VM ID from the response.**

### 3. Run code
```bash
VM_ID="python-1729692845123456789"  # Replace with your VM ID

curl -X POST http://localhost:8787/api/vm/$VM_ID/run \
  -H "Content-Type: application/json" \
  -d '{
    "command": "python -c \"import sys; print(sys.version)\"",
    "timeout": 30
  }'
```

### 4. Check VM status
```bash
curl http://localhost:8787/api/vm/$VM_ID
```

### 5. List all VMs
```bash
curl http://localhost:8787/api/vms
```

### 6. Clean up
```bash
curl -X DELETE http://localhost:8787/api/vm/$VM_ID
```

---

## Error Responses

All errors follow this format:

```json
{
  "error": "descriptive error message",
  "status": 400,
  "message": "descriptive error message",
  "details": "detailed error information (if available)"
}
```

**Common HTTP Status Codes:**
- `200 OK` - Success
- `201 Created` - VM created successfully
- `400 Bad Request` - Invalid request parameters
- `404 Not Found` - VM not found
- `405 Method Not Allowed` - Wrong HTTP method
- `500 Internal Server Error` - Server-side error

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_MODE` | `cli` | Set to `http` or `server` to run as HTTP server |
| `PORT` | `8787` | HTTP server port |
| `AGENT_LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |
| `AGENT_STATE_DIR` | `~/.agent` | State directory location |

---

## CORS Support

The API includes CORS headers allowing cross-origin requests from any domain. This is useful for web frontends.

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

---

## Request Logging

All requests are logged with the following information:
- Method
- Path
- Status code
- Duration
- Client IP

**Example log:**
```json
{
  "level": "info",
  "message": "http request",
  "method": "POST",
  "path": "/api/vm",
  "status": 201,
  "duration": "245.123ms",
  "ip": "127.0.0.1:54321"
}
```

---

## Using with Cloudflare Containers

1. **Build your Go binary:**
```bash
cd /Users/janzheng/Desktop/Projects/ERA/go
make agent
```

2. **Create a Dockerfile** (see `Dockerfile` in this directory)

3. **Deploy to Cloudflare:**
```bash
# Your Go app listens on port 8787
# Cloudflare Workers will route requests to it
```

4. **Worker configuration:**
```javascript
export class Backend extends Container {
  defaultPort = 8787;
  sleepAfter = "2h";
}
```

---

## Testing the API

### Using curl
```bash
# Health check
curl http://localhost:8787/health

# Create VM
curl -X POST http://localhost:8787/api/vm \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu_count":1,"memory_mib":256}'
```

### Using httpie
```bash
# Health check
http GET http://localhost:8787/health

# Create VM
http POST http://localhost:8787/api/vm \
  language=python cpu_count:=1 memory_mib:=256
```

### Using JavaScript/fetch
```javascript
// Create VM
const response = await fetch('http://localhost:8787/api/vm', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    language: 'python',
    cpu_count: 1,
    memory_mib: 256,
    network_mode: 'none'
  })
});

const vm = await response.json();
console.log('VM created:', vm.id);
```

---

## Performance Considerations

- **BoltDB**: State operations are fast (~1-10ms)
- **Concurrent Requests**: Go's HTTP server handles concurrent requests efficiently
- **VM Cache**: In-memory cache for fast VM lookups
- **Graceful Shutdown**: Server handles SIGTERM/SIGINT gracefully

---

## Security Notes

1. **No Authentication**: This version has no built-in authentication. Add middleware if needed.
2. **CORS**: Currently allows all origins (`*`). Restrict in production.
3. **Input Validation**: Basic validation is performed on all inputs.
4. **File Paths**: When using the `file` parameter in run requests, ensure paths are properly validated.

---

## Development

### Run with debug logging
```bash
AGENT_LOG_LEVEL=debug ./agent serve
```

### Custom state directory
```bash
AGENT_STATE_DIR=./dev-state PORT=3000 ./agent serve
```

### Build and run
```bash
make agent
PORT=8787 ./agent serve
```

---

## Next Steps

- [ ] Add authentication middleware
- [ ] Add rate limiting
- [ ] Add WebSocket support for real-time logs
- [ ] Add metrics endpoint (Prometheus)
- [ ] Add OpenAPI/Swagger documentation
- [ ] Add file upload endpoint for VM run
- [ ] Add streaming stdout/stderr

---

## Troubleshooting

### Port already in use
```bash
# Check what's using the port
lsof -i :8787

# Use a different port
PORT=3000 ./agent serve
```

### Cannot connect
```bash
# Check if server is running
curl http://localhost:8787/health

# Check logs
AGENT_LOG_LEVEL=debug ./agent serve
```

### VM operations fail
```bash
# Check VM state directory
ls -la ~/.agent/vms/

# Check logs
cat ~/.agent/vms/*/out/stdout.log
```

