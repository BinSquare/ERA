# ERA Agent Node.js SDK

The ERA Agent Node.js SDK provides an easy-to-use interface for orchestrating microVMs using the ERA Agent HTTP API. This SDK allows you to create VMs, run sandboxed code, and manage the VM lifecycle remotely via HTTP requests.

## Installation

```bash
npm install @era/agent-sdk
```

## Prerequisites

Before using the SDK, you need access to an ERA Agent server instance:
1. A running ERA Agent API server (localhost:8080 by default, or a remote endpoint)
2. The ERA Agent server must have the required dependencies (krunvm, buildah) installed

## Quick Start

First, start the ERA Agent API server:
```bash
# Start the API server on localhost:8080
./agent server
# Or with a specific address:
./agent server --addr :9090
```

Then use the SDK in your application:

```javascript
const ERAAgent = require('@era/agent-sdk');

// Create an instance of the ERA Agent SDK
const agent = new ERAAgent({
  baseUrl: 'http://localhost:8080',  // Address of the ERA Agent API server
  apiKey: 'your-api-key',            // Optional API key if required by server
  timeout: 60000                     // Request timeout in milliseconds
});

// Example: Run a simple Python command in an ephemeral VM
async function runExample() {
  try {
    const result = await agent.runTemp('python', 'python -c "print(\'Hello from sandbox!\')"', {
      cpu: 1,
      mem: 256
    });
    console.log('Command output:', result.stdout);
  } catch (error) {
    console.error('Error:', error.message);
  }
}

runExample();
```

## API Reference

### Constructor
```javascript
const agent = new ERAAgent(options);
```

**Options:**
- `baseUrl` (string): URL of the ERA Agent API server (default: 'http://localhost:8080')
- `apiKey` (string): API key for authentication (optional)
- `timeout` (number): Request timeout in milliseconds (default: 30000)

### Methods

#### `createVM(options)`
Creates a new VM with specified parameters.

**Options:**
- `language` (string): Language runtime (python, javascript, node, ruby, golang) - default: 'python'
- `image` (string): Custom rootfs image
- `cpu` (number): Number of CPUs - default: 1
- `mem` (number): Memory in MB - default: 256
- `network` (string): Network policy (none|allow_all) - default: 'none'
- `persist` (boolean): Enable persistent volume - default: false

**Returns:** Promise resolving to VM record with ID and configuration.

#### `executeInVM(vmId, command, options)`
Executes a command in an existing VM.

**Parameters:**
- `vmId` (string): ID of the VM to execute in
- `command` (string): Command to execute
- `options` (object): Execution options
  - `file` (string): Optional file to stage into /in
  - `timeout` (number): Execution timeout in seconds - default: 30

**Returns:** Promise resolving to execution result with exit code, stdout, and stderr.

#### `runTemp(language, command, options)`
Runs a command in a temporary VM that gets automatically cleaned up.

**Parameters:**
- `language` (string): Language runtime
- `command` (string): Command to execute
- `options` (object): Execution options
  - `cpu` (number): Number of CPUs - default: 1
  - `mem` (number): Memory in MB - default: 256
  - `network` (string): Network policy - default: 'none'
  - `timeout` (number): Execution timeout in seconds - default: 30
  - `file` (string): Optional file to stage into /in

**Returns:** Promise resolving to execution result.

#### `listVMs(options)`
Lists all VMs with optional filtering.

**Options:**
- `status` (string): Filter by status
- `all` (boolean): Include stopped VMs - default: false

**Returns:** Promise resolving to array of VM records.

#### `stopVM(vmId)`
Stops a VM.

**Parameters:**
- `vmId` (string): ID of the VM to stop

**Returns:** Promise resolving when operation completes.

#### `cleanVM(vmId, keepPersist)`
Removes a VM and its resources.

**Parameters:**
- `vmId` (string): ID of the VM to clean
- `keepPersist` (boolean): Whether to keep persistent volumes - default: false

**Returns:** Promise resolving when operation completes.

#### `shell(vmId, shellCommand)`
Starts an interactive shell session in a VM.

**Parameters:**
- `vmId` (string): ID of the VM
- `shellCommand` (string): Shell command to run - default: '/bin/bash'

**Returns:** Promise resolving when shell session ends.

## Complete Example

```javascript
const ERAAgent = require('@era/agent-sdk');

async function completeExample() {
  const agent = new ERAAgent({
    baseUrl: 'http://localhost:8080'  // Adjust to your server address
  });

  try {
    // Create a Python VM
    console.log('Creating VM...');
    const vm = await agent.createVM({
      language: 'python',
      cpu: 1,
      mem: 256,
      network: 'none'
    });
    console.log('Created VM:', vm.id);

    // Execute a command in the VM
    console.log('Executing command in VM...');
    const result = await agent.executeInVM(vm.id, 'python -c "print(42)"');
    console.log('Command result:', result.stdout);

    // Run a temporary Python command
    console.log('Running temporary command...');
    const tempResult = await agent.runTemp('python', 'python -c "print(\'Temporary VM output\')"');
    console.log('Temp result:', tempResult.stdout);

    // List all VMs
    console.log('Listing VMs...');
    const vms = await agent.listVMs({ all: true });
    console.log('Found', vms.length, 'VMs');

    // Clean up the VM
    console.log('Cleaning up...');
    await agent.stopVM(vm.id);
    await agent.cleanVM(vm.id);
    console.log('Cleanup completed');

  } catch (error) {
    console.error('Example failed:', error.message);
  }
}

completeExample();
```

## Error Handling

All methods return promises that reject with error objects on failure. Always wrap SDK calls in try/catch blocks or use .catch() to handle errors appropriately.

## Running the ERA Agent Server

To use the SDK, you need to run an ERA Agent server instance:

```bash
# Build the agent
make

# Run the API server
./agent server                    # Default: http://localhost:8080
./agent server --addr :9090       # Custom address
```

## Security

- Use API keys for authentication if security is required
- Run the ERA Agent server in a secure network environment
- Validate and sanitize all inputs in production applications

## License

MIT