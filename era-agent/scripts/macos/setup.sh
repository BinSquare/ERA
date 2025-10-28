#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	cat <<'EOF'
macOS bootstrap helper for the agent CLI.

Usage:
  scripts/macos/setup.sh [mountpoint]

Steps performed:
  - Verifies that a case-sensitive APFS volume is available to satisfy krunvm's requirements.
  - Installs krunvm and buildah via Homebrew when available.
  - Prepares a writable agent state directory under the chosen volume.

If no mountpoint is supplied, you will be prompted. A sensible default is /Volumes/krunvm.
EOF
	exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "This setup helper only targets macOS." >&2
	exit 1
fi

readonly DEFAULT_MOUNT="/Volumes/krunvm"
mountpoint="${1:-}"

if [[ -z "${mountpoint}" ]]; then
	read -r -p "Please enter the mountpoint for the case-sensitive volume [${DEFAULT_MOUNT}]: " mountpoint
	mountpoint="${mountpoint:-$DEFAULT_MOUNT}"
fi

mountpoint="$(
	python3 - "${mountpoint}" <<'PYCODE'
import os
import sys

if len(sys.argv) < 2:
    raise SystemExit(1)
print(os.path.abspath(sys.argv[1]))
PYCODE
)"

recommended_container="$(diskutil info / 2>/dev/null | awk -F': ' '/APFS Container Reference/ {print $2}' | xargs)"

ensure_case_sensitive_volume() {
	local mount="$1"

	if [[ -d "${mount}" ]]; then
		return 0
	fi

	cat <<'EOF'
The requested mountpoint does not exist.

On macOS, krunvm requires a dedicated, case-sensitive APFS volume.
EOF

	read -r -p "Would you like to create and mount one now? [y/N]: " create_resp
	create_resp="$(printf '%s' "${create_resp}" | tr '[:upper:]' '[:lower:]')"
	if [[ "${create_resp}" != "y" && "${create_resp}" != "yes" ]]; then
		cat <<'EOF'
Please create the volume manually in another terminal, e.g.:

  diskutil apfs addVolume disk3 "Case-sensitive APFS" krunvm

Then re-run this script once the volume is mounted.
EOF
		exit 1
	fi

	if ! command -v diskutil >/dev/null 2>&1; then
		echo "diskutil is not available on PATH; cannot create the volume automatically." >&2
		exit 1
	fi

	local container_disk=""
	while true; do
		local prompt="Enter the APFS container disk identifier (e.g. disk3)"
		if [[ -n "${recommended_container}" ]]; then
			prompt+=" [default: ${recommended_container}, '?' to list]"
		else
			prompt+=" ['?' to list]"
		fi
		read -r -p "${prompt}: " container_disk_raw
		container_disk="$(printf '%s' "${container_disk_raw}" | xargs)"

		if [[ -z "${container_disk}" ]]; then
			if [[ -n "${recommended_container}" ]]; then
				echo "Using recommended container ${recommended_container}."
				container_disk="${recommended_container}"
			else
				echo "No default available. Enter '?' to list containers."
				continue
			fi
		fi

		if [[ "${container_disk}" == "?" ]]; then
			echo "Listing available disks. Look for 'APFS Container Scheme - disk#' and use that disk identifier."
			diskutil list
			if [[ -n "${recommended_container}" ]]; then
				echo "Recommended container (backing /): ${recommended_container}"
			fi
			continue
		fi

		if ! diskutil info "${container_disk}" >/dev/null 2>&1; then
			echo "Could not locate '${container_disk}'. Please choose a valid disk identifier shown by 'diskutil list'." >&2
			continue
		fi

		if ! diskutil apfs list "${container_disk}" >/dev/null 2>&1; then
			echo "'${container_disk}' is not an APFS container. Please select an identifier like disk3 (without partition suffix)." >&2
			continue
		fi

		break
	done

	local volume_name="${mount##*/}"
	if [[ -z "${volume_name}" || "${volume_name}" == "/" ]]; then
		volume_name="era-vol"
	fi

	if [[ ! -d "${mount}" ]]; then
		sudo mkdir -p "${mount}"
	fi

	echo "Creating case-sensitive APFS volume '${volume_name}' on ${container_disk}..."
	if ! sudo -n true >/dev/null 2>&1; then
		cat <<'EOF'
Creating a case-sensitive APFS volume with a custom mount point requires administrative privileges.
Please enter your password when prompted.
EOF
	fi
	if ! sudo diskutil apfs addVolume "${container_disk}" "Case-sensitive APFS" "${volume_name}" -mountpoint "${mount}"; then
		echo "Failed to create the APFS volume. Please resolve the issue and rerun the script." >&2
		exit 1
	fi

	# Give macOS a moment to mount the new volume.
	sleep 2

	if [[ ! -d "${mount}" ]]; then
		echo "Volume creation succeeded, but mountpoint ${mount} is still unavailable." >&2
		exit 1
	fi

	sudo chown "${USER}" "${mount}"
}

ensure_case_sensitive_volume "${mountpoint}"

if [[ ! -d "${mountpoint}" ]]; then
	exit 1
fi

if ! python3 - "$mountpoint" <<'PYCODE'; then
import os
import sys
import uuid

mountpoint = sys.argv[1]
if not os.path.isdir(mountpoint):
    raise SystemExit(1)

tmpdir = os.path.join(mountpoint, ".casecheck." + uuid.uuid4().hex)
try:
    os.mkdir(tmpdir)
    upper = os.path.join(tmpdir, "CaseTest")
    lower = os.path.join(tmpdir, "casetest")
    with open(upper, "w", encoding="utf-8") as fh:
        fh.write("A")
    try:
        with open(lower, "x", encoding="utf-8") as fh:
            fh.write("B")
    except FileExistsError:
        raise SystemExit(1)
finally:
    if os.path.isdir(tmpdir):
        for entry in os.listdir(tmpdir):
            os.remove(os.path.join(tmpdir, entry))
        os.rmdir(tmpdir)
PYCODE
	cat <<'EOF' >&2
The selected mountpoint is not case-sensitive.

Create a case-sensitive APFS volume and mount it at the desired path, then rerun this script.
Example command:

  diskutil apfs addVolume disk3 "Case-sensitive APFS" krunvm
EOF
	exit 1
fi

echo "✔ Case-sensitive volume detected at ${mountpoint}"

state_dir="${mountpoint}/agent-state"
krunvm_dir="${state_dir}/krunvm"
containers_dir="${state_dir}/containers"
containers_storage_dir="${containers_dir}/storage"
containers_runroot_dir="${containers_dir}/runroot"
containers_policy="${containers_dir}/policy.json"
containers_registries="${containers_dir}/registries.conf"

mkdir -p "${krunvm_dir}" "${containers_storage_dir}" "${containers_runroot_dir}"

cat >"${containers_dir}/storage.conf" <<EOF
[storage]
driver = "vfs"
graphroot = "${containers_storage_dir}"
runroot = "${containers_runroot_dir}"
rootless_storage_path = "${containers_storage_dir}"
EOF

cat >"${containers_policy}" <<'EOF'
{
  "default": [
    {
      "type": "insecureAcceptAnything"
    }
  ],
  "transports": {
    "docker": {
      "": [
        {
          "type": "insecureAcceptAnything"
        }
      ]
    }
  }
}
EOF

cat >"${containers_registries}" <<'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "docker.io"
location = "registry-1.docker.io"
blocked = false
insecure = false
EOF

if command -v brew >/dev/null 2>&1; then
	echo "Installing/upgrading krunvm and buildah via Homebrew..."
	missing_packages=()
	for pkg in krunvm buildah; do
		if ! brew list --versions "${pkg}" >/dev/null 2>&1; then
			missing_packages+=("${pkg}")
		fi
	done
	if ((${#missing_packages[@]})); then
		brew install "${missing_packages[@]}"
	else
		brew upgrade krunvm buildah
	fi
	brew_prefix=$(brew --prefix)
else
	cat <<'EOF'
Homebrew is not installed; skipping automatic installation of krunvm/buildah.
Install them manually, e.g.:

  brew install krunvm buildah
EOF
fi

cat <<EOF

Setup complete.

Recommended environment overrides:

  export AGENT_STATE_DIR="${state_dir}"
  export KRUNVM_DATA_DIR="${krunvm_dir}"
  export CONTAINERS_STORAGE_CONF="${containers_dir}/storage.conf"
  export CONTAINERS_STORAGE_CONFIG="${containers_dir}/storage.conf"
  export CONTAINERS_POLICY="${containers_policy}"
  export CONTAINERS_REGISTRIES_CONF="${containers_dir}/registries.conf"
EOF

if [[ -n "${brew_prefix:-}" ]]; then
  echo "  export DYLD_LIBRARY_PATH=\"${brew_prefix}/lib:\$DYLD_LIBRARY_PATH\""
fi

cat <<'EOF'

The agent automatically derives KRUNVM_DATA_DIR from AGENT_STATE_DIR, but exporting it explicitly helps when using buildah/krunvm directly.
EOF
