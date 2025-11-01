# Agent

Minimal scaffold for a secure code-execution runner with a flat Go CLI and supporting Rust FFI.

## Quick Start

### Prerequisites

- macOS: Homebrew (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
- Linux: Package manager (apt, yum, etc.)

### Installation (macOS)

```bash
# 1. Install dependencies
brew install krunvm buildah

# 2. Run setup script (creates case-sensitive volume + agent directories)
cd era-agent
./scripts/macos/setup.sh

# The script will:
# - Create /Volumes/krunvm (case-sensitive APFS) for krunvm
# - Set up ~/agentVM for your VM state and data
# - Generate environment variables

# 3. Load environment variables
source ~/agentVM/.env

# Or permanently add to your shell profile:
cat ~/agentVM/.env >> ~/.zshrc  # or ~/.bashrc

# 4. Build the agent
make

# 5. Test with a simple command
./agent vm temp --language python --cmd "print('Hello, World!')"
```

**Architecture Note**: On macOS, krunvm requires `/Volumes/krunvm` (case-sensitive APFS) for its internal virtio-fs operations. Your agent state, VMs, and data live separately in `~/agentVM` (or `$AGENT_STATE_DIR`). See [this guide](https://sinrega.org/running-microvms-on-m1/) for details.

### Installation (Linux)

```bash
# Install dependencies
# For Ubuntu/Debian: sudo apt-get install buildah krunvm
# For RHEL/CentOS: sudo yum install buildah krunvm

# Build the agent
make

# Run with default settings (may require sudo or specific setup)
sudo ./agent vm temp --language python --cmd "python -c 'print(\"Hello, World!\")'"
```

## Platform Setup Details

### macOS Setup

krunvm on macOS has two storage requirements:

1. **Case-sensitive APFS volume** (`/Volumes/krunvm`) - Required by krunvm for virtio-fs. This is created once and typically stays empty except for krunvm's internal mount points.

2. **Agent state directory** (`~/agentVM` by default) - Your VM metadata, input/output files, persistent storage, and container images.

#### Automated Setup

```bash
./scripts/macos/setup.sh
```

This will:

- Detect or create the case-sensitive APFS volume
- Set up your agent state directory (default: `~/agentVM`)
- Generate environment configuration at `~/agentVM/.env`
- Install/upgrade krunvm and buildah via Homebrew

#### Manual Setup

If you prefer manual setup:

```bash
# 1. Create case-sensitive volume
diskutil apfs addVolume disk3 "Case-sensitive APFS" krunvm

# 2. Create krunvm root structure
sudo mkdir -p /Volumes/krunvm/root/{mounts,vfs,runroot}
sudo chown -R $(whoami):staff /Volumes/krunvm

# 3. Set up agent state directory
mkdir -p ~/agentVM/{krunvm,containers/{storage,runroot},vms,persist}

# 4. Create container storage config
cat > ~/agentVM/containers/storage.conf <<EOF
[storage]
driver = "vfs"
graphroot = "$HOME/agentVM/containers/storage"
runroot = "$HOME/agentVM/containers/runroot"
rootless_storage_path = "$HOME/agentVM/containers/storage"
EOF

# 5. Export environment variables (add to ~/.zshrc)
export AGENT_STATE_DIR="$HOME/agentVM"
export AGENT_ENABLE_GUEST_VOLUMES=1
export CONTAINERS_STORAGE_CONF="$HOME/agentVM/containers/storage.conf"
```

#### Troubleshooting

If you get "Error setting VM mapped volumes":

- Verify `/Volumes/krunvm` exists: `ls -la /Volumes/krunvm`
- Check it's case-sensitive: `diskutil info /Volumes/krunvm | grep -i "case-sensitive"`
- Ensure environment variables are set: `echo $AGENT_STATE_DIR`
- Try: `source ~/agentVM/.env` if you ran the setup script

For more information, see this [guide on running microVMs on M1/M2](https://sinrega.org/running-microvms-on-m1/).

### Linux Setup

- Install `krunvm` and `buildah` using your package manager (the specific installation method may vary)
- Ensure the system is properly configured to run microVMs (may require kernel modules or specific privileges)
- Consider setting `AGENT_STATE_DIR` to a writable location if running as non-root

## Runtime Requirements

- `krunvm` must be installed and available on `$PATH` (Homebrew: `brew install krunvm`; see upstream docs for other platforms).
- `buildah` must also be present because `krunvm` shells out to it for OCI image handling.
- On macOS, `krunvm` requires a case-sensitive APFS volume; see the macOS setup notes above.

## Build

```
make          # builds the agent CLI
make clean    # removes build artifacts (Go cache)
```

## Configuration

- `AGENT_STATE_DIR` overrides the state directory (`/var/lib/agent` when writable, else `${XDG_CONFIG_HOME}/agent` or `~/.agent`). This is the primary configuration you need to set on macOS.
- `AGENT_LOG_LEVEL` or `--log-level` (debug|info|warn|error) controls log verbosity.
- `AGENT_LOG_FILE` or `--log-file` mirrors CLI output to a persistent log file (created if absent).
- `AGENT_ENABLE_GUEST_VOLUMES=1` re-enables mounting `/in`, `/out`, and `/persist` into the guest; the CLI keeps them disabled by default to avoid macOS volume-mapping issues (note: `vm exec --file` requires guest volumes).
- When `AGENT_STATE_DIR` is defined, the launcher will also set `KRUNVM_DATA_DIR` and `CONTAINERS_STORAGE_CONF` so that Buildah uses writable paths on the same case-sensitive volume.
- The macOS helper writes compatible `policy.json`/`registries.conf`; they're automatically picked up when `CONTAINERS_POLICY` and `CONTAINERS_REGISTRIES_CONF` are exported.

## Guest Images

- By default the CLI pulls public base images (`docker.io/library/python:3.11-slim`, `docker.io/library/node:20-slim`, `docker.io/library/ruby:3.2-slim`, or `docker.io/library/golang:1.22-bookworm`). Override the root filesystem with `--image` if you need a custom build.
- A minimal Python image recipe lives in `scripts/images/python-hello/Containerfile` if you want to publish your own tag:
  ```
  make image-python
  ```
  The make target prepares the container-storage config and required environment variables automatically; it also forces a `linux/amd64` build so the artifact is compatible with krunvm. Override `IMAGES_REGISTRY` or `IMAGES_DATE` at invocation time if you want a different tag (e.g. `IMAGES_REGISTRY=myrepo IMAGES_DATE=20251023 make image-python`).

## CLI Surface

```
agent vm create --language <python|javascript|node|ruby|golang> [--image <override>] --cpu --mem --network <none|allow_all> [--persist]
agent vm run --vm <id> --cmd "python main.py" [--file ./main.py] [--timeout 30]
agent vm exec (--cmd "echo hello" [--file ./script.py] | --hello) [--vm <id> ... | --all] [--timeout 30]
agent vm shell --vm <id> [--cmd /bin/bash]                    # Interactive shell access
agent vm temp --language <python> --cmd "<command>" [--timeout <seconds>] --cpu <n> --mem <MiB>    # Ephemeral execution
agent vm list [--status <state>] [--all]
agent vm stop [--vm <id> ... | --all]
agent vm clean [--vm <id> ... | --all] [--keep-persist]
```

- Use `agent vm exec --hello --all` to fan out a language-appropriate "hello world" command across every ready VM.
- Use `--all` with `agent vm stop` or `agent vm clean` to operate on every tracked microVM, or repeat `--vm <id>` to target multiple instances.
- `agent vm list --all` includes stopped instances; without it, the table only shows active VMs.
- `agent vm temp` creates a temporary VM, runs your command, then automatically cleans it up.

## Sample Commands

```shell
# Create microVMs with different language runtimes
agent vm create --language python --cpu 1 --mem 256 --network allow_all
agent vm create --language javascript --cpu 1 --mem 256 --network allow_all
agent vm create --language ruby --cpu 1 --mem 256 --network allow_all
agent vm create --language golang --cpu 1 --mem 256 --network allow_all

# Run language-specific hello world snippets inside targeted VMs
agent vm exec --vm python-<vm-id> --hello
agent vm exec --vm javascript-<vm-id> --cmd 'node -e "console.log(\"hello world\")"'
agent vm exec --vm ruby-<vm-id> --cmd 'ruby -e "puts %(hello world)"'
agent vm exec --vm golang-<vm-id> --cmd 'go run /in/main.go'   # assumes /in/main.go is mounted

# Use ephemeral execution (create, run, cleanup in one command)
agent vm temp --language python --cmd "python -c 'print(\"Hello from temp VM!\")'"

# Use interactive shell to explore a VM
agent vm shell --vm python-<vm-id>

# Stop one VM or everything the CLI tracks
agent vm stop --vm python-<vm-id>
agent vm stop --all

# Clean up specific VMs or all VMs
agent vm clean --vm python-<vm-id>
agent vm clean --all
```

## Cleanup and Uninstallation

### Cleanup Runtime Data

```bash
# Stop all VMs
./agent vm stop --all

# Remove all VMs and their data
./agent vm clean --all

# Remove all state (WARNING: This deletes all VM data, logs, and metadata)
rm -rf "$AGENT_STATE_DIR"
# or if AGENT_STATE_DIR is not set: rm -rf /var/lib/agent  # or ~/.agent
```

### Uninstall Agent

```bash
# Remove the binary
rm ./agent

# Remove all state data (see above)
rm -rf "$AGENT_STATE_DIR"

# Uninstall dependencies (macOS with Homebrew)
brew uninstall krunvm buildah
```

### Reset Environment

If you set environment variables permanently in your shell profile (`~/.bashrc`, `~/.zshrc`, etc.), remove them:

```bash
unset AGENT_STATE_DIR
unset KRUNVM_DATA_DIR
unset CONTAINERS_STORAGE_CONF
unset CONTAINERS_POLICY
unset CONTAINERS_REGISTRIES_CONF
```

## State Persistence

- VM metadata is durably tracked via BoltDB at `/var/lib/agent/agent.db` (override with `AGENT_STATE_DIR`).
- Storage roots are created under `/var/lib/agent/{vms,persist}` with per-VM subdirectories.
- BoltDB is vendored under `vendor/go.etcd.io/bbolt`; run `go mod vendor` after dependency changes to keep it up to date.

## KrunVM Bridge

- `launcher_krunvm.go` shells out to `krunvm create/start/delete`, binding the agent's storage layout into the guest via `--volume`.
- `KRUNVM_DATA_DIR` is automatically pointed at `<state-root>/krunvm`; override `AGENT_STATE_DIR` if you need a different writable location.

## Troubleshooting

### Common Issues

- **"no such file or directory" on macOS**: Make sure you've created a case-sensitive APFS volume and set `AGENT_STATE_DIR`
- **Permission denied**: Ensure the state directory is writable by your user
- **Command not found (krunvm/buildah)**: Install dependencies with `brew install krunvm buildah`
- **"failed to create temporary VM"**: Check that your environment variables are set correctly

### Verification Commands

```bash
# Check if dependencies are available
which krunvm
which buildah

# Check if krunvm works directly
krunvm list

# Verify your environment variables
echo "AGENT_STATE_DIR: $AGENT_STATE_DIR"
echo "KRUNVM_DATA_DIR: $KRUNVM_DATA_DIR"

# Test with a simple ephemeral command
./agent vm temp --language python --cmd "echo 'Setup working!'"
```

## Layout

- `main.go`, `*.go` — host CLI, storage plumbing, krunvm integration, and JSON logging.
- `launcher_krunvm.go` — thin wrapper that shells out to `krunvm`.
- `launcher_libkrun.go` — libkrun implementation (when built with libkrun support).
- `launcher_libkrun_stub.go` — stub implementation when libkrun support is not compiled in.
- `api_server.go` — HTTP API server for remote access to agent functionality.
- `vm_runtime.go` — interface definition for VM launcher implementations.
- `ffi/` — legacy Rust scaffolding kept for experimentation.
- `guest/` — minimal Python entrypoint stub used inside guest images.
- `sdk/` — client SDKs for various languages (Node.js, etc.).
- `vendor/` — vendored Go modules, including BoltDB for durable state.
- `Makefile` — helper targets for building the Go binary.
