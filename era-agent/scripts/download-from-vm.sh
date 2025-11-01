#!/usr/bin/env bash
#
# Download a file or directory from an ERA Agent VM
#
# Usage: ./scripts/download-from-vm.sh <vm-id> <vm-path> <local-path>
#
# Examples:
#   ./scripts/download-from-vm.sh python-123 /app/script.py ./script.py
#   ./scripts/download-from-vm.sh python-123 /app/results.txt ./results.txt
#   ./scripts/download-from-vm.sh python-123 /app/ ./downloads/

set -euo pipefail

if [[ $# -lt 3 ]]; then
    cat >&2 <<'EOF'
Download a file or directory from an ERA Agent VM

Usage: download-from-vm.sh <vm-id> <vm-path> <local-path>

Arguments:
  vm-id       - VM identifier (e.g., python-1761889080622390000)
  vm-path     - Path inside VM (e.g., /app/script.py or /app/)
  local-path  - Local destination path (e.g., ./script.py or ./downloads/)

Examples:
  download-from-vm.sh python-123 /app/script.py ./script.py
  download-from-vm.sh python-123 /app/ ./downloads/
  download-from-vm.sh python-123 /app/results/ ./results/
EOF
    exit 1
fi

VM_ID="$1"
VM_PATH="$2"
LOCAL_PATH="$3"

# Function to download a single file
download_file() {
    local vm_file="$1"
    local local_dest="$2"

    echo "  Downloading: $vm_file -> $local_dest"

    # Create local directory if needed
    local dest_dir=$(dirname "$local_dest")
    if [[ "$dest_dir" != "." && ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir"
    fi

    # Check if file exists
    if ! ./era-agent/agent vm run --vm "$VM_ID" --cmd "test -f '$vm_file'" --timeout 30 2>/dev/null; then
        echo "Error: File not found in VM: $vm_file" >&2
        return 1
    fi

    # Get the stdout log path
    local stdout_log="/Volumes/krunvm/agent-state/vms/$VM_ID/out/stdout.log"
    
    # Clear the log file first
    > "$stdout_log"

    # Encode file to base64 and output via stdout (which goes to stdout.log)
    # Use a temp file on VM to avoid command line length issues
    local vm_tmp="/tmp/era_download_$(basename "$vm_file" | tr '/' '_').b64"
    
    # Encode to temp file, then cat it to stdout
    ./era-agent/agent vm run --vm "$VM_ID" --cmd "base64 < '$vm_file' > '$vm_tmp' && cat '$vm_tmp' && rm -f '$vm_tmp'" --timeout 60

    # Check if we got any output
    if [[ ! -s "$stdout_log" ]]; then
        echo "Error: Failed to read file from VM (empty output)" >&2
        return 1
    fi

    # Read base64 content from stdout log and decode
    # base64 -d handles newlines automatically, but remove any trailing whitespace
    sed 's/[[:space:]]*$//' < "$stdout_log" | base64 -d > "$local_dest" 2>/dev/null || {
        # If that fails, try removing all newlines (some base64 implementations don't use line breaks)
        tr -d '\n\r' < "$stdout_log" | base64 -d > "$local_dest" || {
            echo "Error: Failed to decode base64 content" >&2
            return 1
        }
    }

    echo "    ✓ Downloaded $(wc -c < "$local_dest" | tr -d ' ') bytes"
}

# Function to download a directory
download_directory() {
    local vm_dir="$1"
    local local_dest="$2"

    echo "Downloading directory $vm_dir from VM $VM_ID to $local_dest..."

    # Ensure local destination is a directory
    if [[ ! -d "$local_dest" ]]; then
        mkdir -p "$local_dest"
    fi

    # Ensure local destination ends with /
    [[ "$local_dest" != */ ]] && local_dest="$local_dest/"

    # Get list of all files in the VM directory recursively
    # Use find to list all files with their paths
    local stdout_log="/Volumes/krunvm/agent-state/vms/$VM_ID/out/stdout.log"
    > "$stdout_log"
    
    ./era-agent/agent vm run --vm "$VM_ID" --cmd "find '$vm_dir' -type f 2>/dev/null" --timeout 30

    if [[ ! -s "$stdout_log" ]]; then
        echo "Warning: No files found in $vm_dir" >&2
        return 0
    fi

    # Download each file
    while IFS= read -r vm_file; do
        [[ -z "$vm_file" ]] && continue
        
        # Calculate relative path from VM directory
        local rel_path="${vm_file#$vm_dir}"
        rel_path="${rel_path#/}"  # Remove leading slash if present
        
        # Construct local destination path
        local local_file="${local_dest}${rel_path}"
        
        download_file "$vm_file" "$local_file"
    done < "$stdout_log"

    echo "✓ Directory downloaded successfully"
}

# Check if VM_PATH is a directory or file in the VM
# Test each type and determine what we're dealing with
is_dir=0
is_file=0

# Check if it's a directory (exit code 0 = success)
if ./era-agent/agent vm run --vm "$VM_ID" --cmd "test -d '$VM_PATH'" --timeout 30 >/dev/null 2>&1; then
    is_dir=1
# Check if it's a file (exit code 0 = success)
elif ./era-agent/agent vm run --vm "$VM_ID" --cmd "test -f '$VM_PATH'" --timeout 30 >/dev/null 2>&1; then
    is_file=1
else
    echo "Error: Path not found in VM: $VM_PATH" >&2
    exit 1
fi

# Handle directory or file download
if [[ $is_dir -eq 1 ]]; then
    # It's a directory
    download_directory "$VM_PATH" "$LOCAL_PATH"
elif [[ $is_file -eq 1 ]]; then
    # It's a file
    # If LOCAL_PATH ends with /, append the filename
    if [[ "$LOCAL_PATH" == */ ]]; then
        FILENAME=$(basename "$VM_PATH")
        LOCAL_PATH="${LOCAL_PATH}${FILENAME}"
    fi
    
    echo "Downloading $VM_PATH from VM $VM_ID to $LOCAL_PATH..."
    download_file "$VM_PATH" "$LOCAL_PATH"
    echo "✓ File downloaded successfully"
fi

