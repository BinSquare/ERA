# Agent

Minimal scaffold for a secure code-execution runner with a flat Go CLI and supporting Rust FFI.

## Layout
- `main.go`, `*.go` — host CLI, storage plumbing, krunvm integration, and JSON logging.
- `launcher_krunvm.go` — thin wrapper that shells out to `krunvm`.
- `ffi/` — legacy Rust scaffolding kept for experimentation.
- `guest/` — minimal Python entrypoint stub used inside guest images.
- `vendor/` — vendored Go modules, including BoltDB for durable state.
- `Makefile` — helper targets for building the Go binary.

## Runtime Requirements
- `krunvm` must be installed and available on `$PATH` (Homebrew: `brew install krunvm`; see upstream docs for other platforms).
- `buildah` must also be present because `krunvm` shells out to it for OCI image handling.
- On macOS, `krunvm` requires a case-sensitive APFS volume; see the macOS setup notes below.

## macOS Setup
- Run `scripts/macos/setup.sh` to bootstrap dependencies, validate (or create) a case-sensitive volume, and prepare an agent state directory (the script may prompt for your password to run `diskutil`). The script will also detect your Homebrew installation and recommend the correct value for the `DYLD_LIBRARY_PATH` environment variable, which may be required for `krunvm` to find its dynamic libraries.
- If you prefer to create the dedicated volume manually, open a separate terminal and run (with `sudo` as required):
  ```
  diskutil apfs addVolume disk3 "Case-sensitive APFS" krunvm
  ```
  (replace `disk3` with the identifier reported by `diskutil list`). The operation is non-destructive, does not require `sudo`, and shares space with the source container volume.
- When prompted by the setup script, accept the default mount point (`/Volumes/krunvm`) or provide your own. Afterwards, export the environment variables printed by the script (at minimum `AGENT_STATE_DIR`, `KRUNVM_DATA_DIR`, and `CONTAINERS_STORAGE_CONF`) before invoking `agent` or running `krunvm`/`buildah` directly. The helper now prepares a matching container-storage configuration under the case-sensitive volume so the CLI can run without extra manual steps.
  - The script also writes `policy.json`/`registries.conf` under the same directory so Buildah doesn’t look for root-owned files in `/etc/containers`. Export the variables it prints (`CONTAINERS_POLICY`, `CONTAINERS_REGISTRIES_CONF`) if you invoke Buildah manually.

## Build
```
make          # builds the agent CLI
make clean    # removes build artifacts (Go cache)
```

## Configuration
- `AGENT_STATE_DIR` overrides the state directory (`/var/lib/agent` when writable, else `${XDG_CONFIG_HOME}/agent` or `~/.agent`).
- `AGENT_LOG_LEVEL` or `--log-level` (debug|info|warn|error) controls log verbosity.
- `AGENT_LOG_FILE` or `--log-file` mirrors CLI output to a persistent log file (created if absent).
- `AGENT_ENABLE_GUEST_VOLUMES=1` re-enables mounting `/in`, `/out`, and `/persist` into the guest; the CLI keeps them disabled by default to avoid macOS volume-mapping issues (note: `vm exec --file` requires guest volumes).
- When `AGENT_STATE_DIR` is defined, the launcher will also set `KRUNVM_DATA_DIR` and `CONTAINERS_STORAGE_CONF` so that Buildah uses writable paths on the same case-sensitive volume.
- The macOS helper writes compatible `policy.json`/`registries.conf`; they’re automatically picked up when `CONTAINERS_POLICY` and `CONTAINERS_REGISTRIES_CONF` are exported.

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
agent vm list [--status <state>] [--all]
agent vm stop [--vm <id> ... | --all]
agent vm clean [--vm <id> ... | --all] [--keep-persist]
```

- Use `agent vm exec --hello --all` to fan out a language-appropriate "hello world" command across every ready VM.
- Use `--all` with `agent vm stop` or `agent vm clean` to operate on every tracked microVM, or repeat `--vm <id>` to target multiple instances.
- `agent vm list --all` includes stopped instances; without it, the table only shows active VMs.

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

# Stop one VM or everything the CLI tracks
agent vm stop --vm python-<vm-id>
agent vm stop --all
```

## State Persistence
- VM metadata is durably tracked via BoltDB at `/var/lib/agent/agent.db` (override with `AGENT_STATE_DIR`).
- Storage roots are created under `/var/lib/agent/{vms,persist}` with per-VM subdirectories.
- BoltDB is vendored under `vendor/go.etcd.io/bbolt`; run `go mod vendor` after dependency changes to keep it up to date.

## KrunVM Bridge
- `launcher_krunvm.go` shells out to `krunvm create/start/delete`, binding the agent’s storage layout into the guest via `--volume`.
- `KRUNVM_DATA_DIR` is automatically pointed at `<state-root>/krunvm`; override `AGENT_STATE_DIR` if you need a different writable location.
