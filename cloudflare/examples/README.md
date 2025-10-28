# Cloudflare Examples

Example scripts and utilities for working with ERA Agent on Cloudflare.

## Upload Scripts

These scripts help you upload entire project directories to ERA Agent sessions.

### era-upload.sh (Bash)

Simple bash script for uploading project files.

**Usage:**
```bash
./era-upload.sh <session_id> <project_directory> [api_url]
```

**Example:**
```bash
# Upload current directory
./era-upload.sh my-project-session .

# Upload specific directory
./era-upload.sh data-analysis ./my-data-project

# Use custom API URL
./era-upload.sh my-session ./project https://your-worker.workers.dev
```

**Features:**
- Excludes common build artifacts (node_modules, .git, etc.)
- Progress tracking
- Color-coded output
- Error reporting

### era_upload.py (Python)

Python version with parallel uploads for faster deployment.

**Requirements:**
```bash
pip install requests
```

**Usage:**
```bash
python era_upload.py <session_id> <project_directory> [api_url]
```

**Example:**
```bash
# Upload with parallel uploads (faster)
python era_upload.py my-project ./my-app

# Custom API URL via environment
export ERA_API_URL=https://your-worker.workers.dev
python era_upload.py my-session ./project
```

**Features:**
- Parallel uploads (10 concurrent)
- Automatic content-type detection
- Upload speed statistics
- Better error handling
- Progress tracking

## When to Use Upload Scripts

Use these scripts when you want to:
- Upload an entire codebase to a session
- Set up a development environment in ERA Agent
- Deploy code with dependencies
- Share code across multiple runs

## Example Workflow

```bash
# 1. Create a persistent session
SESSION_ID=$(curl -sf -X POST https://anewera.dev/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"language":"python","persistent":true}' | jq -r '.id')

# 2. Upload your project
python era_upload.py $SESSION_ID ./my-project

# 3. Run code using uploaded files
curl -X POST https://anewera.dev/api/sessions/$SESSION_ID/run \
  -H "Content-Type: application/json" \
  -d '{"code":"import my_module; my_module.main()"}'

# 4. Check files
curl https://anewera.dev/api/sessions/$SESSION_ID/files
```

## Excluded Patterns

Both scripts automatically exclude:
- `node_modules/`
- `.git/`
- `.venv/`, `venv/`
- `__pycache__/`
- `dist/`, `build/`
- `.next/`, `.cache/`
- `.env*` files
- `secrets.*`, `credentials.json`
- `.pyc` files

## Tips

### For Large Projects

Use the Python version for faster uploads:
```bash
python era_upload.py session-id ./large-project
```

### For Simple Projects

Use the bash version (no dependencies):
```bash
./era-upload.sh session-id ./simple-project
```

### Custom Exclusions

Edit the `EXCLUDE_PATTERNS` array in either script to customize what gets excluded.

## Environment Variables

Both scripts support:
- `ERA_API_URL` - Default API URL (default: https://anewera.dev)

```bash
export ERA_API_URL=https://your-worker.workers.dev
./era-upload.sh my-session ./project
```

