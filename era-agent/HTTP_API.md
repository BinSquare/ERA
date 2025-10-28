# ERA Agent HTTP API

The ERA Agent can run as an HTTP server, exposing a REST API for VM management. This is ideal for Cloudflare Containers, Docker deployments, or any cloud environment.

## Running the HTTP Server

### Method 1: Using the `server` command
```bash
./agent server
```

### Method 2: Using environment variable
```bash
AGENT_MODE=http ./agent
```

### Method 3: Custom port
```bash
PORT=3000 ./agent server --addr :3000
```

## API Endpoints

Base URL: `http://localhost:8787`

### Create VM
```bash
POST /api/vm/create
Content-Type: application/json

{
  "language": "python",
  "cpu": 2,
  "memory": 512,
  "network": "none",
  "persist": false,
  "image": ""
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "python-1729692845123456789",
    "language": "python",
    "status": "ready",
    "cpu_count": 2,
    "memory_mib": 512,
    "network_mode": "none",
    "persist": false,
    "created_at": "2025-10-28T12:34:05Z",
    "last_run_at": "0001-01-01T00:00:00Z"
  },
  "status_code": 201
}
```

---

### Execute in VM
```bash
POST /api/vm/execute
Content-Type: application/json

{
  "vm_id": "python-1729692845123456789",
  "command": "python -c \"print('Hello World')\"",
  "timeout": 30,
  "file": ""
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "vm_id": "python-1729692845123456789",
    "exit_code": 0,
    "stdout": "Hello World\n",
    "stderr": "",
    "duration": "1.234s"
  },
  "status_code": 200
}
```

---

### Run Temporary VM (Create + Execute + Cleanup)
```bash
POST /api/vm/temp
Content-Type: application/json

{
  "language": "python",
  "command": "python -c \"import sys; print(sys.version)\"",
  "cpu": 1,
  "memory": 256,
  "timeout": 30
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "vm_id": "python-1729692845987654321",
    "exit_code": 0,
    "stdout": "3.11.x ...",
    "stderr": "",
    "duration": "2.5s"
  },
  "status_code": 200
}
```

---

### List VMs
```bash
GET /api/vm/list
GET /api/vm/list?status=ready
GET /api/vm/list?all=true
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "python-1729692845123456789",
      "language": "python",
      "status": "ready",
      "cpu_count": 2,
      "memory_mib": 512,
      "network_mode": "none",
      "persist": false,
      "created_at": "2025-10-28T12:34:05Z",
      "last_run_at": "2025-10-28T12:35:00Z"
    }
  ],
  "status_code": 200
}
```

---

### Stop VM
```bash
POST /api/vm/stop
Content-Type: application/json

{
  "vm_id": "python-1729692845123456789"
}
```

Or stop all VMs:
```bash
POST /api/vm/stop?all=true
```

---

### Clean VM
```bash
POST /api/vm/clean
Content-Type: application/json

{
  "vm_id": "python-1729692845123456789",
  "keep_persist": false
}
```

Or clean all VMs:
```bash
POST /api/vm/clean?all=true
```

---

## Authentication

Set the `ERA_API_KEY` environment variable to enable API key authentication:

```bash
ERA_API_KEY=your-secret-key ./agent server
```

Then include the API key in requests:

```bash
curl -H "Authorization: Bearer your-secret-key" \
  http://localhost:8787/api/vm/list
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_MODE` | `cli` | Set to `http` or `server` to run as HTTP server |
| `PORT` | `8787` | HTTP server port |
| `AGENT_LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |
| `AGENT_STATE_DIR` | `~/.agent` | State directory location |
| `ERA_API_KEY` | _(none)_ | API key for authentication (optional) |

---

## Docker Deployment

### Using Docker Compose
```bash
# Start the service
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the service
docker-compose down
```

### Using Docker directly
```bash
# Build
docker build -t era-agent:latest .

# Run
docker run -d \
  --name era-agent \
  -p 8787:8787 \
  -e ERA_API_KEY=your-secret-key \
  -v era-agent-state:/var/lib/agent \
  era-agent:latest

# Stop
docker stop era-agent && docker rm era-agent
```

---

## Cloudflare Containers

1. **Build and tag your image:**
```bash
docker build -t your-registry/era-agent:latest .
docker push your-registry/era-agent:latest
```

2. **Configure Cloudflare Worker** (in cloudflare/src/index.ts):
```typescript
export class Backend extends Container {
  defaultPort = 8787;
  sleepAfter = "2h";
}
```

3. **Deploy:**
```bash
cd cloudflare
npm run deploy
```

---

## Testing

```bash
# Health check
curl http://localhost:8787/health

# Create a VM
curl -X POST http://localhost:8787/api/vm/create \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu":1,"memory":256}'

# Run code in temporary VM
curl -X POST http://localhost:8787/api/vm/temp \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "command": "python -c \"print(1+1)\"",
    "timeout": 30
  }'

# List all VMs
curl http://localhost:8787/api/vm/list
```

---

## Error Responses

```json
{
  "success": false,
  "error": "descriptive error message",
  "status_code": 400
}
```

**Common HTTP Status Codes:**
- `200 OK` - Success
- `201 Created` - VM created successfully
- `400 Bad Request` - Invalid request parameters
- `401 Unauthorized` - Missing or invalid API key
- `404 Not Found` - VM not found
- `405 Method Not Allowed` - Wrong HTTP method
- `500 Internal Server Error` - Server-side error
- `501 Not Implemented` - Feature not implemented

---

## Next Steps

- Add WebSocket support for interactive shells
- Add metrics endpoint (Prometheus)
- Add OpenAPI/Swagger documentation
- Add streaming stdout/stderr
- Add file upload endpoint

