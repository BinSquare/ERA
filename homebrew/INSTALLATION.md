# ERA Agent Homebrew Installation

This document describes how to install and use ERA Agent via Homebrew.

## Installation

### Prerequisites
- Homebrew package manager
- On macOS: Xcode Command Line Tools (`xcode-select --install`)

### Install ERA Agent
```bash
# After the formula is available in a tap:
brew install era-agent
```

### Install Dependencies
ERA Agent requires additional dependencies for full functionality:

```bash
brew install krunvm buildah
```

## Post-Installation Setup

### macOS Setup (Required for krunvm)
krunvm requires a case-sensitive APFS volume on macOS. You have two options:

#### Option 1: Run the Setup Script
```bash
# From the source directory (if you have it)
./scripts/brew-install/setup.sh
```

#### Option 2: Manual Setup
1. Create a case-sensitive APFS volume:
   ```bash
   diskutil apfs addVolume disk3 "Case-sensitive APFS" krunvm
   # Replace disk3 with your appropriate disk identifier from `diskutil list`
   ```

2. Set environment variables (add to your shell profile):
   ```bash
   export AGENT_STATE_DIR="/Volumes/krunvm/agent-state"
   export KRUNVM_DATA_DIR="/Volumes/krunvm/agent-state/krunvm"
   export CONTAINERS_STORAGE_CONF="/Volumes/krunvm/agent-state/containers/storage.conf"
   ```

## Usage

### Command Line Interface
```bash
# Create a temporary VM and execute a command
agent vm temp --language python --cmd "python -c 'print(\"Hello from sandbox!\")'"

# Use API server mode
agent server --addr :8080
```

### HTTP API Server
```bash
# Start the API server
agent server --addr :8080

# The server provides endpoints like:
# POST /api/vm/create - Create a new VM
# POST /api/vm/execute - Execute command in VM
# POST /api/vm/temp - Temporary execution
```

### Node.js SDK
Install and use the SDK:

```bash
npm install @era/agent-sdk
```

```javascript
const ERAAgent = require('@era/agent-sdk');

const agent = new ERAAgent({
  baseUrl: 'http://localhost:8080'
});

// Run code in a temporary VM
const result = await agent.runTemp('python', 'print("Hello from Node SDK!")');
console.log(result.stdout);
```

## Environment Variables
- `AGENT_STATE_DIR` - Directory for storing VM state (default: system-dependent)
- `AGENT_LOG_LEVEL` - Logging level (debug, info, warn, error)
- `AGENT_LOG_FILE` - File to log to
- `AGENT_ENABLE_GUEST_VOLUMES` - Enable file staging functionality
- `AGENT_VM_RUNTIME` - VM runtime to use (krunvm, libkrun)
- `ERA_API_KEY` - API key for authentication (when running server mode)

## Troubleshooting

### Common Issues
1. **"Permission denied" or "No such file" on macOS**: Ensure case-sensitive volume is created and mounted
2. **"command not found"**: Make sure `krunvm` and `buildah` are installed
3. **"No VM found"**: Check that environment variables are set correctly

### Verification
```bash
# Check if dependencies are available
which krunvm
which buildah
agent --help

# Test with a simple command
agent vm temp --language python --cmd "echo 'Setup working!'"
```

## Uninstallation

```bash
brew uninstall era-agent
```

Note: This will not remove state directories or user data.