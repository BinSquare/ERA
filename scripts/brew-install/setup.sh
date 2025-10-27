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
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Install with: brew install ${MISSING_DEPS[*]}"
    echo "For full functionality, please install these dependencies."
    echo
    read -r -p "Would you like to install them now? [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        brew install "${MISSING_DEPS[@]}"
    else
        echo "⚠️  Warning: ERA Agent will have limited functionality without these dependencies."
    fi
else
    echo "✅ All dependencies found: krunvm, buildah"
fi

# macOS-specific checks
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo
    echo "macOS Setup"
    echo "-----------"
    echo "krunvm requires a case-sensitive APFS volume on macOS."
    echo 
    
    # Check if we already have a case-sensitive volume set up
    if [[ -n "${AGENT_STATE_DIR:-}" ]] && [[ -d "${AGENT_STATE_DIR}" ]]; then
        echo "✅ AGENT_STATE_DIR is already set to: ${AGENT_STATE_DIR}"
    else
        echo "You'll need to set up a case-sensitive volume and environment variables."
        echo
        
        # Guide for case-sensitive volume setup
        echo "Option 1: Use the existing setup script (requires admin privileges)"
        echo "  sudo /path/to/era-agent-source/scripts/macos/setup.sh"
        echo
        echo "Option 2: Manual setup (see ERA Agent documentation)"
        echo "  You'll need to set these environment variables:"
        echo "  - AGENT_STATE_DIR (e.g., /Volumes/krunvm/agent-state)"
        echo "  - KRUNVM_DATA_DIR (usually same as AGENT_STATE_DIR/krunvm)"
        echo "  - CONTAINERS_STORAGE_CONF (for container operations)"
        echo
    fi
else
    echo "Linux detected - no special volume requirements"
fi

echo
echo "Setup Complete!"
echo "==============="
echo "You can now use ERA Agent:"
echo
echo "  # Run as API server"
echo "  agent server --addr :8080"
echo
echo "  # Run temporary execution"  
echo "  agent vm temp --language python --cmd 'python -c \"print(\\\"Hello World\\\")\"'"
echo
echo "For Node.js SDK usage, install the package:"
echo "  npm install @era/agent-sdk"
echo
echo "Then connect to your server instance:"
echo "  const agent = new ERAAgent({ baseUrl: 'http://localhost:8080' });"