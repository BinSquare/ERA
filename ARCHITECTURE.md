# ERA Architecture

Understanding how ERA works under the hood.

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         User                                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ interacts with
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    React Ink CLI                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  • QuickStart Component (Interactive)                 │  │
│  │  • VMCreate, VMRun, VMStatus Components               │  │
│  │  • CLI Router (meow)                                  │  │
│  │  • Agent Wrapper (execa)                              │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ executes binary
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      Go Agent                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  • CLI Parser (flags)                                 │  │
│  │  • VMService (orchestration logic)                    │  │
│  │  • BoltVMStore (state persistence)                    │  │
│  │  • Storage Management                                 │  │
│  │  • Logger (structured JSON)                           │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ calls FFI
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                     Rust FFI Layer                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  • C ABI Interface (CGO)                              │  │
│  │  • VM Launcher Implementation                         │  │
│  │  • Launch, Stop, Cleanup functions                    │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ manages
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   VM Instances                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  • Python 3.11 Runtime                                │  │
│  │  • Node.js 20 Runtime                                 │  │
│  │  • Isolated File Systems                              │  │
│  │  • Resource Limits (CPU/Memory)                       │  │
│  │  • Network Policies                                   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. React Ink CLI (TypeScript/Node.js)

**Location:** `/cli/src/`

**Purpose:** User-facing interactive terminal interface

**Key Files:**
- `cli.tsx` - Main entry point, argument parsing
- `agent.ts` - Go binary wrapper using `execa`
- `components/` - React components for UI

**Responsibilities:**
- Parse user input
- Render beautiful terminal UI
- Execute Go agent binary
- Parse JSON responses
- Read and display output files
- Handle errors gracefully

**Dependencies:**
- `ink` - React for CLIs
- `meow` - CLI argument parser
- `execa` - Process execution
- `chalk` - Terminal colors

### 2. Go Agent (Go)

**Location:** `/go/`

**Purpose:** VM orchestration and state management

**Key Files:**
- `main.go` - Entry point
- `cli.go`, `cli_vm.go` - Command parsing
- `vm_service.go` - Core VM operations
- `vm_store.go` - BoltDB persistence
- `launcher_ffi.go` - Rust FFI interface
- `logging.go` - Structured logging

**Responsibilities:**
- Parse command-line arguments
- Manage VM lifecycle
- Persist VM state in BoltDB
- Manage storage layout
- Call Rust FFI for VM operations
- Return JSON responses
- Write stdout/stderr to files

**Dependencies:**
- `bbolt` - Embedded database
- `CGO` - C/Rust interop

### 3. Rust FFI Layer (Rust)

**Location:** `/go/ffi/`

**Purpose:** Low-level VM management

**Key Files:**
- `src/lib.rs` - FFI entry points
- `src/vm.rs` - VM implementation
- `include/vmlauncher.h` - C header

**Responsibilities:**
- Expose C ABI functions
- Launch VMs
- Stop VMs
- Clean up resources

**Build:** `cargo build`

### 4. VM Instances

**Purpose:** Isolated execution environments

**Characteristics:**
- Read-only rootfs
- Configurable CPU/memory
- Network policies
- Persistent volumes (optional)
- User isolation (UID 65532)

## Data Flow

### Creating a VM

```
User enters: era create --language python --cpu 2 --mem 512

1. CLI parses arguments
   └─> { language: 'python', cpu: 2, mem: 512 }

2. CLI executes: ../go/agent vm create --language python --cpu 2 --mem 512
   └─> execa spawns process

3. Go agent creates VM record
   └─> Generates ID: python-1729692845123456789
   └─> Prepares storage: ~/.agent/vms/python-1729692845123456789/
   └─> Resolves rootfs: agent/python:3.11-20251023

4. Go calls Rust FFI
   └─> agent_launch_vm(&config)

5. Rust launches VM
   └─> Creates isolated environment

6. Go saves state
   └─> BoltDB write: VM record

7. Go returns JSON
   └─> { "level": "info", "id": "python-...", ... }

8. CLI parses and displays
   └─> ✓ VM created successfully!
       VM ID: python-1729692845123456789
```

### Running Code

```
User enters: era run --vm python-123 --cmd "python hello.py" --file ./hello.py

1. CLI validates arguments
   └─> Checks VM ID, command, file exist

2. CLI executes Go agent
   └─> ../go/agent vm run --vm python-123 --cmd "..." --file ./hello.py

3. Go loads VM record
   └─> BoltDB read: VM state
   └─> Checks status == "running"

4. Go stages input file
   └─> Copy: ./hello.py → ~/.agent/vms/python-123/in/hello.py

5. Go executes command
   └─> Currently: logs command (full execution pending)

6. Go writes output
   └─> ~/.agent/vms/python-123/out/stdout.log
   └─> ~/.agent/vms/python-123/out/stderr.log

7. Go returns paths
   └─> { "stdout": "/path/to/stdout.log", "stderr": "...", ... }

8. CLI reads output files
   └─> readFile(stdout), readFile(stderr)

9. CLI displays formatted output
   └─> ─── stdout ───
       Hello from VM!
```

## Storage Layout

```
State Directory (e.g., ~/.agent/)
├── agent.db                    # BoltDB - VM metadata
├── vms/
│   └── python-1729692845123456789/
│       ├── in/                 # Input files staged here
│       │   └── hello.py
│       └── out/                # Execution output
│           ├── stdout.log
│           └── stderr.log
└── persist/
    └── python-1729692845123456789/  # Persistent storage (if --persist)
        └── data/
```

## State Management

### VM States

```
provisioning → running → stopped
                  ↓
              cleaned (deleted)
```

### State Transitions

```
CREATE:  none → provisioning → running
RUN:     running → running (updates LastRunAt)
STOP:    running → stopped
CLEAN:   * → deleted (removed from DB and disk)
```

### Persistence

**BoltDB Schema:**
```
Bucket: "vms"
  Key: VM ID (string)
  Value: VMRecord (JSON encoded)
    {
      "id": "python-123...",
      "language": "python",
      "status": "running",
      "storage": { ... },
      "created_at": "...",
      ...
    }
```

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `AGENT_STATE_DIR` | `~/.agent` | State directory location |
| `AGENT_LOG_LEVEL` | `info` | Logging verbosity |

### Storage Paths

Resolved in order:
1. `$AGENT_STATE_DIR` (if set)
2. `/var/lib/agent` (if writable)
3. `~/.config/agent` (if UserConfigDir available)
4. `~/.agent` (if HomeDir available)
5. `/tmp/agent` (fallback)

## Communication Protocol

### CLI → Go Agent

**Transport:** Process execution (stdin/stdout)

**Format:** Command-line arguments

**Example:**
```bash
./agent vm create --language python --cpu 2 --mem 512
```

### Go Agent → CLI

**Transport:** stdout

**Format:** JSON (one per log line)

**Example:**
```json
{
  "level": "info",
  "message": "vm created",
  "id": "python-1729692845123456789",
  "language": "python",
  "rootfs": "agent/python:3.11-20251023",
  "cpu_count": 2,
  "memoryMiB": 512,
  "created_at": "2025-10-23T12:34:05Z"
}
```

### Go Agent → Rust FFI

**Transport:** CGO (C ABI)

**Format:** C structures

**Example:**
```c
typedef struct {
    const char* id;
    const char* rootfs_image;
    unsigned int cpu_count;
    unsigned int memory_mib;
    const char* network_mode;
} AgentVMConfig;

int agent_launch_vm(const AgentVMConfig* config);
```

## Error Handling

### CLI Layer
- Validates input arguments
- Catches execution errors
- Displays user-friendly messages
- Returns appropriate exit codes

### Go Layer
- Validates VM state
- Checks file operations
- Wraps FFI errors
- Logs structured errors
- Returns error JSON

### Rust Layer
- Returns error codes
- C-compatible error handling
- No panics across FFI boundary

## Concurrency

### CLI
- Single-threaded Node.js
- Async I/O (file reads)
- Sequential execution

### Go
- Mutex-protected VM cache
- Concurrent-safe BoltDB
- Safe FFI calls
- Goroutine-safe logging

### Rust
- Thread-safe VM management
- No shared state across FFI

## Security Considerations

1. **VM Isolation**: Each VM runs in isolated environment
2. **User Isolation**: Guest processes run as UID 65532
3. **Network Policies**: Default is no network access
4. **Read-only Rootfs**: Base images are immutable
5. **Resource Limits**: CPU and memory constraints
6. **Path Sanitization**: VM IDs and paths are sanitized

## Performance

### CLI Startup
- ~100ms (Node.js + React Ink)

### VM Creation
- ~1-5s (depends on FFI implementation)

### Code Execution
- Variable (depends on script)

### State Operations
- ~1-10ms (BoltDB is fast)

## Extending ERA

### Adding a New Language

1. **Go:** Add case to `resolveRootFS()` in `vm_service.go`
2. **CLI:** Add option to language selector
3. **Test:** Create example script in `cli/examples/`

### Adding New Commands

1. **Go:** Add handler to `cli_vm.go`
2. **Go:** Implement in `vm_service.go`
3. **CLI:** Add component to `cli/src/components/`
4. **CLI:** Add route to `cli.tsx`

### Custom VM Configurations

Currently hardcoded in `VMCreateOptions`. To extend:
1. Add flags to Go CLI
2. Pass through to VM service
3. Forward to Rust FFI
4. Update CLI component

## Future Enhancements

- Full VM execution integration
- VM listing and status queries
- Real-time output streaming
- Multi-VM orchestration
- Remote state backends
- VM snapshots
- Resource monitoring
- Network proxy support

## Debugging

### Enable Debug Logging

```bash
export AGENT_LOG_LEVEL=debug
npm run dev
```

### Inspect State

```bash
# View BoltDB contents (requires boltbrowser or similar)
cd ~/.agent
# VM state is in agent.db

# View output directly
cat ~/.agent/vms/<vm-id>/out/stdout.log
```

### Trace Execution

```bash
# Go agent with debug logs
cd go
AGENT_LOG_LEVEL=debug ./agent vm create --language python --cpu 1 --mem 256

# CLI with verbose output
cd cli
npm run dev create -- --language python
```

