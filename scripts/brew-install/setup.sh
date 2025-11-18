#!/bin/bash

# Homebrew installation setup script for ERA Agent
# This script helps users set up ERA Agent after Homebrew installation

set -euo pipefail

echo "ERA Agent Homebrew Setup"
echo "========================"
echo

# Check if ERA Agent is installed
if ! command -v agent >/dev/null 2>&1; then
    echo "❌ ERA Agent binary not found in PATH"
    echo "Please install with: brew install era-agent"
    exit 1
fi

echo "✅ ERA Agent binary found: $(which agent)"

# Check if dependencies are installed
MISSING_DEPS=()
for dep in krunvm buildah; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "❌ Missing required dependencies: ${MISSING_DEPS[*]}"
    echo
    echo "Install them with:"
    echo "  brew install ${MISSING_DEPS[*]}"
    echo
    echo "For Linux, install via your package manager:"
    echo "  Ubuntu/Debian: sudo apt-get install krunvm buildah"
    echo "  CentOS/RHEL: sudo yum install krunvm buildah"
    exit 1
fi

echo "✅ All dependencies found"

# Check if we're on macOS (required for krunvm setup)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo
    echo "macOS detected. Setting up krunvm case-sensitive volume..."
    
    # Check if the volume exists
    if ! mount | grep -q "/Volumes/krunvm"; then
        echo "❌ Case-sensitive volume /Volumes/krunvm not found"
        echo
        echo "You need to create a case-sensitive APFS volume for krunvm."
        echo "Run the macOS setup script:"
        echo "  $(brew --prefix era-agent)/libexec/setup/setup.sh"
        exit 1
    else
        echo "✅ Case-sensitive volume found"
        
        # Check if environment variables are set
        if [[ -z "${AGENT_STATE_DIR:-}" ]]; then
            echo
            echo "Environment variables not set. Please add these to your shell profile:"
            echo
            echo "export AGENT_STATE_DIR=\"/Volumes/krunvm/agent-state\""
            echo "export KRUNVM_DATA_DIR=\"/Volumes/krunvm/agent-state/krunvm\""
            echo "export CONTAINERS_STORAGE_CONF=\"/Volumes/krunvm/agent-state/containers/storage.conf\""
            echo
            echo "Then run: source ~/.zshrc  # or ~/.bash_profile"
        else
            echo "✅ Environment variables appear to be set"
        fi
    fi
else
    echo "Linux detected. Ensure krunvm and buildah are properly configured."
    echo "You may need to update your PATH if needed."
fi

echo
echo "🎉 ERA Agent setup complete!"
echo
echo "To start using ERA Agent:"
echo "  agent serve"
echo
echo "To test with a simple command:"
echo "  agent vm temp --language python --cmd \"python -c 'print(\\\"Hello, World!\\\")'\""
echo