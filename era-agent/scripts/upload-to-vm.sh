#!/usr/bin/env bash
#
# Upload a file or directory to an ERA Agent VM (workaround for broken volume mounting)
#
# Usage: ./scripts/upload-to-vm.sh <vm-id> <local-path> <vm-path> [--run]
#
# Examples:
#   ./scripts/upload-to-vm.sh python-123 script.py /app/script.py
#   ./scripts/upload-to-vm.sh python-123 script.py /app/script.py --run
#   ./scripts/upload-to-vm.sh python-123 ./my-dir /app/

set -euo pipefail

if [[ $# -lt 3 ]]; then
    cat >&2 <<'EOF'
Upload a file or directory to an ERA Agent VM

Usage: upload-to-vm.sh <vm-id> <local-path> <vm-path> [--run]

Arguments:
  vm-id       - VM identifier (e.g., python-1761889080622390000)
  local-path  - Path to local file or directory to upload
  vm-path     - Destination path inside VM (e.g., /app/script.py or /app/)
  --run       - Execute the file after uploading (optional, single files only)

Examples:
  upload-to-vm.sh python-123 script.py /app/script.py
  upload-to-vm.sh python-123 script.py /app/script.py --run
  upload-to-vm.sh python-123 ./my-dir /app/
EOF
    exit 1
fi

VM_ID="$1"
LOCAL_PATH="$2"
VM_PATH="$3"
RUN_AFTER="${4:-}"

if [[ ! -e "$LOCAL_PATH" ]]; then
    echo "Error: Path not found: $LOCAL_PATH" >&2
    exit 1
fi

# Function to upload a single file
upload_file() {
    local local_file="$1"
    local vm_dest="$2"

    echo "  Uploading: $local_file -> $vm_dest"

    # Get directory path
    VM_DIR=$(dirname "$vm_dest")
    VM_TMP="/tmp/era_upload_$(basename "$vm_dest").b64"

    # Create directory first
    ./era-agent/agent vm run --vm "$VM_ID" --cmd "mkdir -p '$VM_DIR'" --timeout 30

    # For large files, we need to chunk the base64 to avoid command line length limits
    # Write base64 content to a temp file in chunks, then decode it
    # Use a loop that writes ~800 char chunks at a time (conservative limit after double-encoding)
    local chunk_size=800
    local encoded_content
    encoded_content=$(base64 -i "$local_file")
    
    # Calculate number of chunks
    local content_len=${#encoded_content}
    local num_chunks=$(( (content_len + chunk_size - 1) / chunk_size ))
    
    # Clear temp file on VM first
    ./era-agent/agent vm run --vm "$VM_ID" --cmd "> '$VM_TMP'" --timeout 30
    
    # Write chunks sequentially
    for ((i=0; i<num_chunks; i++)); do
        local start=$((i * chunk_size))
        
        # Extract chunk using bash substring (base64 doesn't contain single quotes, so no escaping needed)
        local chunk="${encoded_content:$start:$chunk_size}"
        
        # Append chunk to temp file on VM
        ./era-agent/agent vm run --vm "$VM_ID" --cmd "printf '%s' '$chunk' >> '$VM_TMP'" --timeout 30
    done
    
    # Decode the base64 temp file and write to destination
    ./era-agent/agent vm run --vm "$VM_ID" --cmd "base64 -d < '$VM_TMP' > '$vm_dest' && rm -f '$VM_TMP'" --timeout 30
}

# Check if it's a directory
if [[ -d "$LOCAL_PATH" ]]; then
    echo "Uploading directory $LOCAL_PATH to VM $VM_ID at $VM_PATH..."

    # Ensure VM_PATH ends with /
    [[ "$VM_PATH" != */ ]] && VM_PATH="$VM_PATH/"

    # Find all files recursively and upload each one
    while IFS= read -r -d '' file; do
        # Calculate relative path
        rel_path="${file#$LOCAL_PATH}"
        rel_path="${rel_path#/}"  # Remove leading slash if present

        # Construct VM destination path
        vm_dest="${VM_PATH}${rel_path}"

        upload_file "$file" "$vm_dest"
    done < <(find "$LOCAL_PATH" -type f -print0)

    echo "✓ Directory uploaded successfully"

elif [[ -f "$LOCAL_PATH" ]]; then
    # Single file mode

    # Detect file type for execution
    EXT="${LOCAL_PATH##*.}"
    case "$EXT" in
        py)
            EXECUTOR="python"
            ;;
        js)
            EXECUTOR="node"
            ;;
        sh|bash)
            EXECUTOR="bash"
            ;;
        *)
            EXECUTOR=""
            ;;
    esac

    # If VM_PATH ends with /, append the filename
    # Also check if VM_PATH is a directory in the VM (even without trailing slash)
    if [[ "$VM_PATH" == */ ]]; then
        FILENAME=$(basename "$LOCAL_PATH")
        VM_PATH="${VM_PATH}${FILENAME}"
    elif ./era-agent/agent vm run --vm "$VM_ID" --cmd "test -d '$VM_PATH'" --timeout 30 >/dev/null 2>&1; then
        # VM_PATH is a directory, append filename
        FILENAME=$(basename "$LOCAL_PATH")
        VM_PATH="${VM_PATH}/${FILENAME}"
    fi

    echo "Uploading $LOCAL_PATH to VM $VM_ID at $VM_PATH..."

    # Get directory path
    VM_DIR=$(dirname "$VM_PATH")
    VM_TMP="/tmp/era_upload_$(basename "$VM_PATH").b64"

    # Create directory first
    ./era-agent/agent vm run --vm "$VM_ID" --cmd "mkdir -p '$VM_DIR'" --timeout 30

    # For large files, we need to chunk the base64 to avoid command line length limits
    # Write base64 content to a temp file in chunks, then decode it
    # Use a loop that writes ~800 char chunks at a time (conservative limit after double-encoding)
    chunk_size=800
    encoded_content=$(base64 -i "$LOCAL_PATH")
    
    # Calculate number of chunks
    content_len=${#encoded_content}
    num_chunks=$(( (content_len + chunk_size - 1) / chunk_size ))
    
    # Clear temp file on VM first
    ./era-agent/agent vm run --vm "$VM_ID" --cmd "> '$VM_TMP'" --timeout 30
    
    # Write chunks sequentially
    for ((i=0; i<num_chunks; i++)); do
        start=$((i * chunk_size))
        
        # Extract chunk using bash substring (base64 doesn't contain single quotes, so no escaping needed)
        chunk="${encoded_content:$start:$chunk_size}"
        
        # Append chunk to temp file on VM
        ./era-agent/agent vm run --vm "$VM_ID" --cmd "printf '%s' '$chunk' >> '$VM_TMP'" --timeout 30
    done
    
    # Decode the base64 temp file and write to destination
    decode_cmd="base64 -d < '$VM_TMP' > '$VM_PATH' && rm -f '$VM_TMP'"
    
    # Add execution if requested
    if [[ "$RUN_AFTER" == "--run" && -n "$EXECUTOR" ]]; then
        decode_cmd="$decode_cmd && $EXECUTOR '$VM_PATH'"
    fi
    
    # Upload (and optionally run)
    ./era-agent/agent vm run --vm "$VM_ID" --cmd "$decode_cmd" --timeout 30

    echo "✓ File uploaded successfully"

    if [[ "$RUN_AFTER" == "--run" ]]; then
        echo ""
        echo "Output:"
        cat "/Volumes/krunvm/agent-state/vms/$VM_ID/out/stdout.log"
    fi
fi
