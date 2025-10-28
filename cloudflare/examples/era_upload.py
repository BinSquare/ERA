#!/usr/bin/env python3
"""
ERA Agent Project Upload Script
Uploads all source files from a local directory to an ERA Agent session with parallel uploads
Usage: python era_upload.py <session_id> <project_directory> [api_url]

Features:
- Parallel uploads for faster deployment
- Automatic exclusion of common build artifacts
- Progress tracking and error reporting
- Color-coded output
"""

import os
import sys
import mimetypes
from pathlib import Path
from typing import List, Tuple, Set
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

# Configuration
DEFAULT_API_URL = 'https://anewera.dev'
MAX_WORKERS = 10  # Parallel uploads
TIMEOUT = 30  # Request timeout in seconds

# Colors for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    RESET = '\033[0m'

# Patterns to exclude (these will be checked against path parts)
EXCLUDE_PATTERNS: Set[str] = {
    'node_modules',
    '.git',
    '.venv',
    'venv',
    '__pycache__',
    'dist',
    'build',
    '.next',
    '.cache',
    'coverage',
    '.DS_Store',
    '.env',
    '.env.local',
    '.env.production',
    '.env.development',
    'secrets.json',
    'secrets.yaml',
    'secrets.yml',
    'credentials.json',
}

# File extensions to exclude
EXCLUDE_EXTENSIONS: Set[str] = {
    '.pyc',
    '.pyo',
    '.pyd',
    '.so',
    '.dylib',
    '.log',
}

def print_color(message: str, color: str = Colors.RESET):
    """Print colored message to terminal."""
    print(f"{color}{message}{Colors.RESET}")

def should_exclude(path: Path, project_dir: Path) -> bool:
    """Check if path should be excluded based on patterns."""
    # Check if any part of the path matches exclude patterns
    rel_path = path.relative_to(project_dir)
    parts = set(rel_path.parts)

    if parts & EXCLUDE_PATTERNS:
        return True

    # Check file extension
    if path.suffix in EXCLUDE_EXTENSIONS:
        return True

    # Check filename
    if path.name in EXCLUDE_PATTERNS:
        return True

    return False

def get_files(project_dir: Path) -> List[Path]:
    """Get all files to upload, excluding patterns."""
    files = []

    for file_path in project_dir.rglob('*'):
        if file_path.is_file() and not should_exclude(file_path, project_dir):
            files.append(file_path)

    return files

def get_content_type(file_path: Path) -> str:
    """Detect content type for file."""
    content_type, _ = mimetypes.guess_type(str(file_path))
    return content_type or 'application/octet-stream'

def format_size(size_bytes: int) -> str:
    """Format file size in human-readable format."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.1f}{unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f}TB"

def upload_file(
    session_id: str,
    project_dir: Path,
    file_path: Path,
    api_url: str
) -> Tuple[str, bool, str, int]:
    """
    Upload a single file.
    Returns: (relative_path, success, error_message, file_size)
    """
    rel_path = file_path.relative_to(project_dir)
    url = f"{api_url}/api/sessions/{session_id}/files/{rel_path}"

    try:
        # Read file
        with open(file_path, 'rb') as f:
            content = f.read()

        file_size = len(content)

        # Detect content type
        content_type = get_content_type(file_path)
        headers = {'Content-Type': content_type}

        # Upload
        response = requests.put(
            url,
            data=content,
            headers=headers,
            timeout=TIMEOUT
        )

        if response.status_code == 200:
            return (str(rel_path), True, '', file_size)
        else:
            error_msg = f"HTTP {response.status_code}"
            try:
                error_detail = response.json().get('error', '')
                if error_detail:
                    error_msg += f": {error_detail}"
            except:
                pass
            return (str(rel_path), False, error_msg, file_size)

    except requests.exceptions.Timeout:
        return (str(rel_path), False, "Timeout", 0)
    except Exception as e:
        return (str(rel_path), False, str(e), 0)

def main():
    # Parse arguments
    if len(sys.argv) < 3:
        print_color("ERA Agent Project Upload Script", Colors.BLUE)
        print_color("Usage: python era_upload.py <session_id> <project_directory> [api_url]", Colors.RED)
        print("\nExample: python era_upload.py my-project ./my-app")
        print("\nEnvironment variables:")
        print("  ERA_API_URL  - Default API URL (optional)")
        sys.exit(1)

    session_id = sys.argv[1]
    project_dir = Path(sys.argv[2])
    api_url = sys.argv[3] if len(sys.argv) > 3 else os.environ.get('ERA_API_URL', DEFAULT_API_URL)

    # Validate project directory
    if not project_dir.exists():
        print_color(f"Error: Directory '{project_dir}' does not exist", Colors.RED)
        sys.exit(1)

    if not project_dir.is_dir():
        print_color(f"Error: '{project_dir}' is not a directory", Colors.RED)
        sys.exit(1)

    # Print header
    print_color("📦 ERA Agent Project Upload", Colors.BLUE)
    print_color("=" * 60, Colors.BLUE)
    print(f"Session ID:  {Colors.GREEN}{session_id}{Colors.RESET}")
    print(f"Directory:   {Colors.GREEN}{project_dir}{Colors.RESET}")
    print(f"API URL:     {Colors.GREEN}{api_url}{Colors.RESET}")
    print()

    # Get files to upload
    print_color("🔍 Scanning for files...", Colors.YELLOW)
    start_time = datetime.now()

    files = get_files(project_dir)
    total_files = len(files)

    if total_files == 0:
        print_color("No files to upload!", Colors.RED)
        sys.exit(1)

    # Calculate total size
    total_size = sum(f.stat().st_size for f in files)

    print_color(f"📁 Found {total_files} files ({format_size(total_size)} total)", Colors.GREEN)
    print()

    # Upload files in parallel
    print_color("📤 Uploading files...", Colors.BLUE)
    uploaded = 0
    failed = 0
    uploaded_size = 0
    errors = []

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        # Submit all upload tasks
        futures = {
            executor.submit(upload_file, session_id, project_dir, file_path, api_url): file_path
            for file_path in files
        }

        # Process completed uploads
        for future in as_completed(futures):
            rel_path, success, error, file_size = future.result()

            if success:
                uploaded += 1
                uploaded_size += file_size
                print_color(
                    f"✅ [{uploaded + failed}/{total_files}] {rel_path}",
                    Colors.GREEN
                )
            else:
                failed += 1
                error_msg = f"❌ [{uploaded + failed}/{total_files}] {rel_path} ({error})"
                print_color(error_msg, Colors.RED)
                errors.append((rel_path, error))

    # Calculate duration
    duration = (datetime.now() - start_time).total_seconds()

    # Print summary
    print()
    print_color("=" * 60, Colors.BLUE)

    if failed == 0:
        print_color("✨ Upload complete!", Colors.GREEN)
        print(f"   {Colors.GREEN}✅ Successfully uploaded: {uploaded} files ({format_size(uploaded_size)}){Colors.RESET}")
    else:
        print_color("⚠️  Upload complete with errors", Colors.YELLOW)
        print(f"   {Colors.GREEN}✅ Successfully uploaded: {uploaded} files ({format_size(uploaded_size)}){Colors.RESET}")
        print(f"   {Colors.RED}❌ Failed: {failed} files{Colors.RESET}")

        if errors:
            print()
            print_color("Failed files:", Colors.YELLOW)
            for path, error in errors:
                print(f"  {Colors.RED}•{Colors.RESET} {path}: {error}")

    print(f"\n⏱️  Duration: {duration:.1f}s")

    if uploaded > 0:
        avg_speed = uploaded_size / duration if duration > 0 else 0
        print(f"📊 Average speed: {format_size(int(avg_speed))}/s")

    # Print next steps
    print()
    print_color("Next steps:", Colors.BLUE)
    print(f"  1. Check files: curl {api_url}/api/sessions/{session_id}/files")
    print(f"  2. Run code:    curl -X POST {api_url}/api/sessions/{session_id}/run -d '{{\"code\": \"...\"}}'")
    print(f"  3. View logs:   curl {api_url}/api/sessions/{session_id}")

    # Exit with error code if any uploads failed
    sys.exit(failed)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print()
        print_color("\n⚠️  Upload interrupted by user", Colors.YELLOW)
        sys.exit(130)
    except Exception as e:
        print()
        print_color(f"❌ Unexpected error: {e}", Colors.RED)
        import traceback
        traceback.print_exc()
        sys.exit(1)
