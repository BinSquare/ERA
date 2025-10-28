# Agent

Minimal scaffold for a secure code-execution runner with a flat Go CLI and supporting Rust FFI.

## Quick Start

### Prerequisites
- macOS: Homebrew (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
- Linux: Package manager (apt, yum, etc.)

### Installation (macOS)
```bash
# 1. Install dependencies
brew tap slp/krun
brew install krunvm buildah

# 2. Setup case-sensitive volume and state directory
./scripts/macos/setup.sh

# 3. Follow the script's output to set environment variables (paste these into the terminal)
export AGENT_STATE_DIR="/Volumes/krunvm/agent-state"  # example from setup script
export KRUNVM_DATA_DIR="/Volumes/krunvm/agent-state/krunvm"
export CONTAINERS_STORAGE_CONF="/Volumes/krunvm/agent-state/containers/storage.conf"

# 4. Build the agent
make

# 5. Test with a simple command
./agent vm temp --language python --cmd 'python -c "print(\"Hello, World!\")"'
```

### Installation (Linux)
```bash
# Install dependencies
# For Ubuntu/Debian: sudo apt-get install buildah krunvm
# For RHEL/CentOS: sudo yum install buildah krunvm

# Build the agent
make

# Run with default settings (may require sudo or specific setup)
sudo ./agent vm temp --language python --cmd 'python -c "print(\"Hello, World!\")"'
```

## Platform Setup Details

### macOS Setup
- Run `scripts/macos/setup.sh` to bootstrap dependencies, validate (or create) a case-sensitive volume, and prepare an agent state directory (the script may prompt for your password to run `diskutil`). The script will also detect your Homebrew installation and recommend the correct value for the `DYLD_LIBRARY_PATH` environment variable, which may be required for `krunvm` to find its dynamic libraries.

- If you prefer to create the dedicated volume manually, open a separate terminal and run (with `sudo` as required):
  ```
  diskutil apfs addVolume disk3 "Case-sensitive APFS" krunvm
  ```
  (replace `disk3` with the identifier reported by `diskutil list`). The operation is non-destructive, does not require `sudo`, and shares space with the source container volume.

- When prompted by the setup script, accept the default mount point (`/Volumes/krunvm`) or provide your own. Afterwards, export the environment variables printed by the script (at minimum `AGENT_STATE_DIR`, `KRUNVM_DATA_DIR`, and `CONTAINERS_STORAGE_CONF`) before invoking `agent` or running `krunvm`/`buildah` directly. The helper now prepares a matching container-storage configuration under the case-sensitive volume so the CLI can run without extra manual steps.
  - The script also writes `policy.json`/`registries.conf` under the same directory so Buildah doesn't look for root-owned files in `/etc/containers`. Export the variables it prints (`CONTAINERS_POLICY`, `CONTAINERS_REGISTRIES_CONF`) if you invoke Buildah manually.

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
agent vm temp --language python --cmd 'python -c "print(\"Hello from temp VM!\")"'

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
./agent vm temp --language python --cmd 'echo "Setup working!"'
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