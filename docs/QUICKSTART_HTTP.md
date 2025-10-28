# ERA Agent HTTP Server - Quick Start

Get the ERA Agent HTTP server running in under 5 minutes.

## 🚀 Quick Start

### 1. Build the Agent

```bash
cd /Users/janzheng/Desktop/Projects/ERA/go
make agent
```

This will:
- Build the Rust FFI layer
- Compile the Go binary
- Output the `agent` executable

### 2. Start the HTTP Server

```bash
./agent serve
```

Or with custom settings:

```bash
PORT=3000 AGENT_LOG_LEVEL=debug ./agent serve
```

You should see:
```json
{
  "level": "info",
  "message": "starting agent in http server mode",
  "port": "8787"
}
{
  "level": "info",
  "message": "http server starting",
  "port": "8787"
}
```

### 3. Test It!

Open a new terminal and run:

```bash
# Health check
curl http://localhost:8787/health

# Or run the full test suite
./test-http-server.sh
```

---

## 📋 Using Make Commands

The Makefile has convenient targets:

```bash
# Build and start server
make serve

# Start with debug logging
make serve-dev

# Test HTTP endpoints (requires server running)
make test-http
```

---

## 🐳 Docker Quick Start

### Using Docker Compose (Easiest)

```bash
# Start the server
docker-compose up -d

# View logs
docker-compose logs -f

# Test it
curl http://localhost:8787/health

# Stop it
docker-compose down
```

### Using Docker Directly

```bash
# Build image
make docker-build

# Run container
make docker-run

# View logs
docker logs -f era-agent

# Stop and clean up
make docker-clean
```

---

## 🧪 Testing the API

### Manual Testing with curl

```bash
# 1. Create a Python VM
curl -X POST http://localhost:8787/api/vm \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "cpu_count": 1,
    "memory_mib": 256,
    "network_mode": "none"
  }'

# Response will include a VM ID like: "python-1729692845123456789"
# Save it to a variable:
VM_ID="python-1729692845123456789"

# 2. Get VM details
curl http://localhost:8787/api/vm/$VM_ID

# 3. Run code in the VM
curl -X POST http://localhost:8787/api/vm/$VM_ID/run \
  -H "Content-Type: application/json" \
  -d '{
    "command": "python -c \"print('Hello from VM!'); print(2+2)\"",
    "timeout": 30
  }'

# 4. List all VMs
curl http://localhost:8787/api/vms

# 5. Stop the VM
curl -X POST http://localhost:8787/api/vm/$VM_ID/stop

# 6. Delete the VM
curl -X DELETE http://localhost:8787/api/vm/$VM_ID
```

### Automated Testing

Run the test script that tests all endpoints:

```bash
./test-http-server.sh
```

This script will:
- ✓ Check server health
- ✓ Create a VM
- ✓ Get VM details
- ✓ List all VMs
- ✓ Run code
- ✓ Stop VM
- ✓ Delete VM
- ✓ Verify cleanup

---

## 🌐 Complete Example Workflow

Here's a complete Python example:

```python
import requests
import json

BASE_URL = "http://localhost:8787"

# 1. Create VM
response = requests.post(f"{BASE_URL}/api/vm", json={
    "language": "python",
    "cpu_count": 1,
    "memory_mib": 256,
    "network_mode": "none"
})
vm = response.json()
vm_id = vm["id"]
print(f"Created VM: {vm_id}")

# 2. Run code
response = requests.post(f"{BASE_URL}/api/vm/{vm_id}/run", json={
    "command": "python -c 'import sys; print(sys.version)'",
    "timeout": 30
})
result = response.json()
print(f"Output:\n{result['stdout']}")

# 3. List VMs
response = requests.get(f"{BASE_URL}/api/vms")
vms = response.json()
print(f"Total VMs: {vms['count']}")

# 4. Clean up
response = requests.delete(f"{BASE_URL}/api/vm/{vm_id}")
print(f"Cleaned up: {response.json()['status']}")
```

---

## 📚 JavaScript/Fetch Example

```javascript
const BASE_URL = 'http://localhost:8787';

async function testAgent() {
  // Create VM
  const createResp = await fetch(`${BASE_URL}/api/vm`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      language: 'python',
      cpu_count: 1,
      memory_mib: 256
    })
  });
  const vm = await createResp.json();
  console.log('VM created:', vm.id);

  // Run code
  const runResp = await fetch(`${BASE_URL}/api/vm/${vm.id}/run`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      command: 'python -c "print(42 * 2)"',
      timeout: 30
    })
  });
  const result = await runResp.json();
  console.log('Output:', result.stdout);

  // Clean up
  await fetch(`${BASE_URL}/api/vm/${vm.id}`, { method: 'DELETE' });
  console.log('Cleaned up!');
}

testAgent();
```

---

## ⚙️ Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_MODE` | `cli` | Set to `http` to run as server |
| `PORT` | `8787` | HTTP server port |
| `AGENT_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |
| `AGENT_STATE_DIR` | `~/.agent` | State directory location |

### Examples

```bash
# Custom port
PORT=3000 ./agent serve

# Debug logging
AGENT_LOG_LEVEL=debug ./agent serve

# Custom state directory
AGENT_STATE_DIR=/tmp/agent-state ./agent serve

# All together
PORT=3000 AGENT_LOG_LEVEL=debug AGENT_STATE_DIR=/tmp/agent ./agent serve
```

---

## 🔧 Troubleshooting

### Server won't start

**Port already in use:**
```bash
# Check what's using port 8787
lsof -i :8787

# Use a different port
PORT=3001 ./agent serve
```

**Build errors:**
```bash
# Rebuild from scratch
make clean
make agent
```

### Can't connect to server

**Check if server is running:**
```bash
curl http://localhost:8787/health
```

**Check logs:**
```bash
AGENT_LOG_LEVEL=debug ./agent serve
```

### VM operations fail

**Check state directory:**
```bash
ls -la ~/.agent/
ls -la ~/.agent/vms/
```

**Check VM logs:**
```bash
cat ~/.agent/vms/*/out/stdout.log
cat ~/.agent/vms/*/out/stderr.log
```

---

## 📖 Next Steps

- **Full API Documentation**: See [HTTP_API.md](./HTTP_API.md)
- **Cloudflare Deployment**: See [cloudflare-worker-example.js](./cloudflare-worker-example.js)
- **Docker Guide**: See [Dockerfile](./Dockerfile)
- **CLI Usage**: See [README.md](./README.md)

---

## 🚢 Deploying to Production

### Cloudflare Containers

1. Build and push Docker image:
```bash
make cf-build
docker tag era-agent:cloudflare your-registry/era-agent:latest
docker push your-registry/era-agent:latest
```

2. Deploy Worker (see [cloudflare-worker-example.js](./cloudflare-worker-example.js))

### Traditional VPS/Cloud

1. Build and deploy:
```bash
# On your server
git clone your-repo
cd ERA/go
make agent
```

2. Create systemd service:
```ini
[Unit]
Description=ERA Agent HTTP Server
After=network.target

[Service]
Type=simple
User=agent
Environment="AGENT_MODE=http"
Environment="PORT=8787"
WorkingDirectory=/opt/era-agent
ExecStart=/opt/era-agent/agent serve
Restart=always

[Install]
WantedBy=multi-user.target
```

3. Start service:
```bash
sudo systemctl enable era-agent
sudo systemctl start era-agent
```

---

## 💡 Tips

1. **Use JSON pretty printing**: Add `| jq .` to curl commands
2. **Save VM IDs**: Store them in variables for easier testing
3. **Monitor logs**: Use debug mode during development
4. **Test health endpoint**: Quick way to check if server is running
5. **Use the test script**: Validates everything is working

---

## 🆘 Getting Help

- **API Docs**: [HTTP_API.md](./HTTP_API.md)
- **Examples**: [test-http-server.sh](./test-http-server.sh)
- **Main README**: [README.md](./README.md)
- **Architecture**: [../ARCHITECTURE.md](../ARCHITECTURE.md)

---

Happy coding! 🎉

