# ERA Agent

A Go-based VM orchestration system for running isolated code execution environments. This agent manages lightweight VMs with support for Python and Node.js runtimes, providing sandboxed execution with configurable CPU, memory, and network policies.

## Features

- **Multi-language Support**: Python 3.11 and Node.js 20 runtimes
- **Isolated Execution**: Each VM runs in a sandboxed environment
- **Resource Control**: Configurable CPU cores and memory allocation
- **Network Policies**: Support for `none` (isolated) or `allow_all` network modes
- **Persistent Storage**: Optional persistent volumes that survive VM lifecycle
- **State Management**: Built-in VM state tracking using BoltDB
- **FFI Integration**: Rust-based VM launcher via CGO

## Prerequisites

- **Go**: 1.21 or higher
- **Rust**: Latest stable (for building FFI layer)
- **Cargo**: Rust package manager

## Installation

### 1. Clone the repository

```bash
cd /path/to/ERA/go
```

### 2. Build the FFI layer (Rust)

```bash
cd ffi
cargo build
cd ..
```

### 3. Build the agent binary

```bash
go build -o agent .
```

Or use the Makefile:

```bash
make agent
```

This will:
- Build the Rust FFI library
- Compile the Go binary
- Output the `agent` executable

## Usage

### Basic Command Structure

```bash
./agent [--log-level <level>] <command> <subcommand> [options]
```

### Environment Variables

- `AGENT_LOG_LEVEL`: Set log level (`debug`, `info`, `warn`, `error`). Default: `info`
- `AGENT_STATE_DIR`: Override default state directory. Default: `/var/lib/agent` or `~/.agent`

### Commands

#### 1. Create a VM

```bash
./agent vm create --language <python|node> \
                  --cpu <n> \
                  --mem <MiB> \
                  --network <none|allow_all> \
                  [--image <override>] \
                  [--persist]
```

**Example:**
```bash
./agent vm create --language python --cpu 2 --mem 512 --network none
```

**Output:**
```json
{
  "level": "info",
  "message": "vm created",
  "id": "python-1729692845123456789",
  "language": "python",
  "rootfs": "agent/python:3.11-20251023",
  "cpu_count": 2,
  "memoryMiB": 512,
  "network": "none",
  "persisted": false,
  "created_at": "2025-10-23T12:34:05Z"
}
```

**Note the VM ID** - you'll need it for subsequent commands.

#### 2. Run Code in VM

```bash
./agent vm run --vm <vm-id> \
               --cmd "<command>" \
               --timeout <seconds> \
               [--file <path>]
```

**Example:**
```bash
./agent vm run --vm python-1729692845123456789 \
               --cmd "python /workspace/in/hello.py" \
               --timeout 30 \
               --file ./hello.py
```

**Output:**
```json
{
  "level": "info",
  "message": "vm run",
  "vm": "python-1729692845123456789",
  "exit_code": 0,
  "stdout": "/path/to/state/vms/python-1729692845123456789/out/stdout.log",
  "stderr": "/path/to/state/vms/python-1729692845123456789/out/stderr.log",
  "duration": "1.234s"
}
```

The `stdout` and `stderr` paths contain the execution output.

#### 3. Stop a VM

```bash
./agent vm stop --vm <vm-id>
```

**Example:**
```bash
./agent vm stop --vm python-1729692845123456789
```

#### 4. Clean Up a VM

```bash
./agent vm clean --vm <vm-id> [--keep-persist]
```

**Example:**
```bash
./agent vm clean --vm python-1729692845123456789
```

Use `--keep-persist` to retain the persistent volume if the VM was created with `--persist`.

## Hello World Example

Here's a complete example of creating a Python VM, running a hello world script, and retrieving the output:

### Step 1: Create a Python script

```bash
cat > hello.py << 'EOF'
print("Hello from ERA Agent!")
print("This is running in an isolated VM")

# Calculate something
result = 42 * 2
print(f"The answer is: {result}")
EOF
```

### Step 2: Create a VM

```bash
./agent vm create --language python --cpu 1 --mem 256 --network none
```

**Output:**
```json
{"level":"info","message":"vm created","id":"python-1729692845123456789",...}
```

**Copy the VM ID** from the output.

### Step 3: Run your script

```bash
VM_ID="python-1729692845123456789"  # Replace with your VM ID

./agent vm run --vm "$VM_ID" \
               --cmd "python /workspace/in/hello.py" \
               --timeout 30 \
               --file ./hello.py
```

**Output:**
```json
{
  "level": "info",
  "message": "vm run",
  "vm": "python-1729692845123456789",
  "exit_code": 0,
  "stdout": "/Users/janzheng/.agent/vms/python-1729692845123456789/out/stdout.log",
  "stderr": "/Users/janzheng/.agent/vms/python-1729692845123456789/out/stderr.log",
  "duration": "0.123s"
}
```

### Step 4: Read the output

```bash
# Read stdout
cat /Users/janzheng/.agent/vms/python-1729692845123456789/out/stdout.log
```

**Output:**
```
executed: python /workspace/in/hello.py
```

*(Note: The current implementation logs the command. Full execution integration pending.)*

### Step 5: Get output in your program

If you're calling this from Go code or another program, you can parse the JSON output and read the files:

```go
package main

import (
    "encoding/json"
    "fmt"
    "os"
    "os/exec"
)

type VMRunResult struct {
    Level      string `json:"level"`
    Message    string `json:"message"`
    VM         string `json:"vm"`
    ExitCode   int    `json:"exit_code"`
    StdoutPath string `json:"stdout"`
    StderrPath string `json:"stderr"`
    Duration   string `json:"duration"`
}

func main() {
    // Run the command
    cmd := exec.Command("./agent", "vm", "run",
        "--vm", "python-1729692845123456789",
        "--cmd", "python /workspace/in/hello.py",
        "--timeout", "30",
        "--file", "./hello.py")
    
    output, err := cmd.CombinedOutput()
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        return
    }
    
    // Parse the JSON result
    var result VMRunResult
    if err := json.Unmarshal(output, &result); err != nil {
        fmt.Printf("Parse error: %v\n", err)
        return
    }
    
    // Read the output files
    stdout, _ := os.ReadFile(result.StdoutPath)
    stderr, _ := os.ReadFile(result.StderrPath)
    
    fmt.Printf("Exit Code: %d\n", result.ExitCode)
    fmt.Printf("Duration: %s\n", result.Duration)
    fmt.Printf("Stdout:\n%s\n", string(stdout))
    fmt.Printf("Stderr:\n%s\n", string(stderr))
}
```

### Step 6: Clean up

```bash
./agent vm clean --vm "$VM_ID"
```

## Node.js Example

```bash
# Create a Node.js script
cat > hello.js << 'EOF'
console.log("Hello from Node.js!");
console.log("Running in ERA Agent VM");
console.log(`Result: ${40 + 2}`);
EOF

# Create VM
./agent vm create --language node --cpu 1 --mem 256 --network none

# Run script (replace VM_ID with your actual ID)
./agent vm run --vm node-1729692845987654321 \
               --cmd "node /workspace/in/hello.js" \
               --timeout 30 \
               --file ./hello.js

# Clean up
./agent vm clean --vm node-1729692845987654321
```

## Development

### Run with debug logging

```bash
AGENT_LOG_LEVEL=debug ./agent vm create --language python --cpu 1 --mem 256 --network none
```

### Custom state directory

```bash
AGENT_STATE_DIR=./my-state ./agent vm create --language python --cpu 1 --mem 256 --network none
```

### Build targets

```bash
# Build everything
make all

# Build just the agent
make agent

# Build just the FFI layer
make ffi

# Format Go code
make fmt

# Clean build artifacts
make clean

# Run test VM creation
make test
```

## Architecture

- **Go Layer**: CLI, VM service, state management
- **Rust FFI**: VM launcher interface via CGO
- **BoltDB**: Persistent VM state storage
- **Storage Layout**: 
  - `/workspace/in`: Input files staged here
  - `/workspace/out`: Execution logs (stdout/stderr)
  - `/workspace/persist`: Optional persistent storage

## Troubleshooting

### VM creation fails

- Ensure the FFI layer is built: `cd ffi && cargo build`
- Check state directory permissions
- Verify sufficient system resources

### Cannot read output files

- The paths are absolute - use them directly
- Check file permissions in the state directory

### State directory

Default locations (tried in order):
1. `$AGENT_STATE_DIR` (if set)
2. `/var/lib/agent`
3. `~/.config/agent`
4. `~/.agent`
5. `/tmp/agent` (fallback)

## HTTP Server Mode

The ERA Agent can also run as an HTTP server, making it easy to deploy to cloud platforms like Cloudflare Workers.

### Running Locally as HTTP Server

```bash
# Start the HTTP server on port 8787
./agent serve

# Or with custom port
PORT=8080 ./agent serve

# Test the server
curl http://localhost:8787/health
```

### HTTP API Endpoints

See [HTTP_API.md](HTTP_API.md) for complete API documentation.

Quick examples:

```bash
# Health check
curl http://localhost:8787/health

# Create a VM
curl -X POST http://localhost:8787/api/vm \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu_count":1,"memory_mib":256}'

# Run code in VM (use VM ID from above)
curl -X POST http://localhost:8787/api/vm/python-123/run \
  -H "Content-Type: application/json" \
  -d '{"command":"python -c \"print(42)\"","timeout":30}'
```

## Deploying to Cloudflare

This ERA Agent is designed to be deployed to Cloudflare Workers with Containers.

### Prerequisites

- **Docker Desktop** running locally
- **Node.js** 18+ installed
- **Cloudflare account** (free tier works)

### Quick Deploy

From the project root (`ERA-cf-clean/`):

```bash
# One-command deploy
./build-deploy.sh

# This will:
# 1. Build the Go agent binary
# 2. Validate the Docker build
# 3. Deploy to Cloudflare (builds & pushes automatically)
```

### Manual Deploy

```bash
# 1. Build the agent
make agent

# 2. Deploy to Cloudflare
cd ../cloudflare
npm install
npx wrangler login
npx wrangler deploy
```

**No Docker Hub needed!** Cloudflare builds from the Dockerfile and pushes to their registry automatically.

### After Deployment

Your API will be live at:
```
https://era-agent.YOUR_SUBDOMAIN.workers.dev
```

Test it:
```bash
curl https://era-agent.YOUR_SUBDOMAIN.workers.dev/health
```

### How It Works

1. **Dockerfile** packages the `agent` binary into a container
2. **Cloudflare Worker** routes requests to the container
3. **wrangler deploy** builds locally and pushes to Cloudflare's registry
4. Your API is live on Cloudflare's global network!

### More Information

- [Cloudflare Deployment Guide](../cloudflare/README.md)
- [Quick Reference](../cloudflare/QUICK_REFERENCE.md)
- [Detailed Deploy Steps](../cloudflare/DEPLOY.md)

## License

See project root for license information.
