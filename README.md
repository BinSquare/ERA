# ERA Agent - Sandbox to run ai generated code

Run untrusted or AI-generated code locally inside microVMs that behave like containers for great devX, 200ms launch time, and better security.

There's a fully managed cloud layer, globally deployed Worker/API, jump to [cloudflare/README.md](cloudflare/README.md).

[![Publish Release](https://github.com/BinSquare/ERA/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/BinSquare/ERA/actions/workflows/release.yml)

## Quick Start

### Prerequisites

- macOS 13+/Linux with hardware virtualization enabled
- Homebrew (on mac) and a Go 1.21 toolchain
- `krunvm` and `buildah`

### Install (Homebrew)

```bash
brew tap your-username/era-agent
brew install era-agent
brew install krunvm buildah
```

Run the post-install helper to prepare the case-sensitive volume/state dir on macOS:

```bash
$(brew --prefix era-agent)/libexec/setup/setup.sh
```

### Install (From Source)

```bash
git clone https://github.com/your-username/era-agent.git
cd era-agent
brew install krunvm buildah   # or use your distro packages
make agent
./agent vm temp --language python --cmd "python -c 'print(\"Hello\")'"
```

Full platform-specific steps (macOS volume setup, Linux env vars, troubleshooting) live in [era-agent/README.md](era-agent/README.md).

## 🎥 Demo Video

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

## ⚙ Configuration Highlights

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
