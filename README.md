# ERA - Sandbox to run AI generated code. 

Run untrusted or AI-generated code locally with the security guarantees of microVM and ease of use from containers.

There's a managed cloud layer through cloudflare, globally deployed Worker/API, jump to [cloudflare/README.md](cloudflare/README.md).

This project is early stage, experimental. We will be changing and breaking things temporarily as we port towards rust. Expect bugs, please report them.

[![Go Version](https://img.shields.io/badge/Go-1.21-00ADD8?logo=go)](https://go.dev/doc/devel/release)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

**What runs where**

- `agent` CLI, Buildah, and krunvm all run on your local machine inside a case-sensitive volume.
- [Experimental] The optional Cloudflare Worker package allows you to package and execute code on cloudflare's remote sandbox.

## Quick Start

### installation options

#### option 1: homebrew (recommended)

```bash
# 1. install the tap
brew tap binsquare/era-agent-cli
brew tap slp/krun

# 2. install era agent
brew install binsquare/era-agent-cli/era-agent

# 3. install dependencies
brew install krunvm buildah

# 4. verify the CLI is on PATH
agent vm exec --help

# 4. follow platform-specific setup (see below)
```

#### option 2: from source

```bash
# 1. install dependencies
brew install krunvm buildah  # on macos

# 2. clone the repository
git clone https://github.com/binsquare/era
cd era-agent

# 3. build the agent
make

# 4. follow platform-specific setup (see below)
```

### Installation (macOS)

```bash
brew tap binsquare/era-agent-cli
brew install binsquare/era-agent-cli/era-agent
brew install krunvm buildah

# the CLI is installed as `agent` on your PATH
agent vm exec --help
```

Run the post-install helper to prepare the case-sensitive volume/state dir on macOS:

```bash
$(brew --prefix era-agent)/libexec/setup/setup.sh
```

## platform setup details

### homebrew installation setup

if you installed era agent via homebrew, use the setup script from the installed location:

```bash
# for macos users with homebrew installation
$(brew --prefix era-agent)/libexec/setup/setup.sh

# or run the setup script directly after installation
$(brew --prefix)/bin/era-agent-setup  # if setup script is linked separately
```

### macos setup

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

Full platform-specific steps (macOS volume setup, Linux env vars, troubleshooting) live in [era-agent/README.md](era-agent/README.md).

## Demo Video

[![Demo Video](https://img.youtube.com/vi/Si4evw3pglY/0.jpg)](https://www.youtube.com/watch?v=Si4evw3pglY)

A demo video showing how to install and use the CLI tool is available in the [era-agent directory](era-agent/README.md). This video covers:

- Installing dependencies and compiling the CLI tool
- Creating and accessing local VMs
- Running code and agents through commands or scripts
- Uploading and downloading files to/from a VM

## Core Commands

```bash
# create a long-running VM
agent vm create --language python --cpu 1 --mem 256 --network allow_all

# run something inside it
agent vm exec --vm <id> --cmd "python -c 'print(\"hi\")'"

# ephemeral one-off execution
agent vm temp --language javascript --cmd "node -e 'console.log(42)'"

# inspect / cleanup
agent vm list
agent vm stop --all
agent vm clean --all
```

Supported `--language` values: `python`, `javascript`/`node`/`typescript`, `go`, `ruby`. Override the base image with `--image` if you need a custom runtime.

## Configurations

- `AGENT_STATE_DIR`: writable directory for VM metadata, krunvm state, and Buildah storage. The macOS setup script prints the correct exports.
- `AGENT_LOG_LEVEL` (`debug|info|warn|error`) and `AGENT_LOG_FILE`: control logging.
- `AGENT_ENABLE_GUEST_VOLUMES=1`: re-enable `/in`, `/out`, `/persist` mounts for advanced workflows.

See [era-agent/README.md](era-agent/README.md#configuration) for every tunable.

## Testing Locally

```bash
cd era-agent
make agent
./agent vm temp --language python --cmd "python -c 'print(\"Smoke test\")'"
```

Integration helpers and sample recipes live under `examples/`, `recipes/`, and `docs/`.

## Need the Hosted API?

To deploy ERA as a Cloudflare Worker with Durable Object-backed sessions and HTTP APIs:

- Follow [cloudflare/README.md](cloudflare/README.md) for setup, local Wrangler dev, and deployment.
- The Worker reuses the same Go agent primitives but adds session orchestration, package caching, and REST endpoints.

## Additional Docs

- [era-agent/README.md](era-agent/README.md) – detailed CLI usage, setup scripts, troubleshooting.
- [cloudflare/README.md](cloudflare/README.md) – Worker/API deployment guide.
- [docs/](docs/) – HTTP quickstart, storage notes, MCP adapters.
- [recipes/README.md](recipes/README.md) – ready-to-run workflows.
- [examples/README.md](examples/README.md) – language samples.

## 📄 License

Apache 2.0
