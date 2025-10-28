#!/bin/bash
# ERA Agent Project Upload Script
# Uploads all source files from a local directory to an ERA Agent session
# Usage: ./era-upload.sh <session_id> <project_directory> [api_url]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SESSION_ID="$1"
PROJECT_DIR="$2"
API_URL="${3:-${ERA_API_URL:-https://anewera.dev}}"

if [ -z "$SESSION_ID" ] || [ -z "$PROJECT_DIR" ]; then
  echo -e "${RED}Usage: $0 <session_id> <project_directory> [api_url]${NC}"
  echo "Example: $0 my-project ./my-app"
  echo ""
  echo "Environment variables:"
  echo "  ERA_API_URL  - Default API URL (optional)"
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo -e "${RED}Error: Directory '$PROJECT_DIR' does not exist${NC}"
  exit 1
fi

echo -e "${BLUE}📦 ERA Agent Project Upload${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Session ID:  ${GREEN}$SESSION_ID${NC}"
echo -e "Directory:   ${GREEN}$PROJECT_DIR${NC}"
echo -e "API URL:     ${GREEN}$API_URL${NC}"
echo ""

# Patterns to exclude (glob patterns)
declare -a EXCLUDE_PATTERNS=(
  "*/node_modules/*"
  "*/.git/*"
  "*/.venv/*"
  "*/venv/*"
  "*/__pycache__/*"
  "*/dist/*"
  "*/build/*"
  "*/.next/*"
  "*/.cache/*"
  "*/coverage/*"
  "*/.DS_Store"
  "*.pyc"
  "*/.env"
  "*/.env.local"
  "*/.env.production"
  "*/.env.development"
  "*/secrets.*"
  "*/credentials.json"
)

# Build find command with exclusions
FIND_CMD="find \"$PROJECT_DIR\" -type f"
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
  FIND_CMD="$FIND_CMD ! -path \"$pattern\""
done

# Count total files
echo -e "${YELLOW}🔍 Scanning for files...${NC}"
TOTAL_FILES=$(eval "$FIND_CMD" | wc -l | tr -d ' ')

if [ "$TOTAL_FILES" -eq 0 ]; then
  echo -e "${RED}No files found to upload!${NC}"
  exit 1
fi

echo -e "${GREEN}📁 Found $TOTAL_FILES files to upload${NC}"
echo ""

# Progress tracking
UPLOADED=0
FAILED=0
SKIPPED=0

# Create temp file for logging errors
ERROR_LOG=$(mktemp)

# Upload files
echo -e "${BLUE}📤 Uploading files...${NC}"
eval "$FIND_CMD" -print0 | while IFS= read -r -d '' file; do
  # Get relative path
  rel_path="${file#$PROJECT_DIR/}"

  # Skip if path is exactly the project dir
  if [ "$file" = "$PROJECT_DIR" ]; then
    continue
  fi

  # Upload file
  response=$(curl -s -w "\n%{http_code}" -X PUT \
    "$API_URL/api/sessions/$SESSION_ID/files/$rel_path" \
    --data-binary "@$file" \
    -H "Content-Type: application/octet-stream" 2>&1)

  http_code=$(echo "$response" | tail -n1)

  UPLOADED=$((UPLOADED + 1))

  if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✅${NC} [$UPLOADED/$TOTAL_FILES] $rel_path"
  else
    FAILED=$((FAILED + 1))
    echo -e "${RED}❌${NC} [$UPLOADED/$TOTAL_FILES] $rel_path ${RED}(HTTP $http_code)${NC}"
    echo "$rel_path: HTTP $http_code" >> "$ERROR_LOG"
  fi
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Summary
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✨ Upload complete!${NC}"
  echo -e "   ${GREEN}✅ Successfully uploaded: $UPLOADED files${NC}"
else
  echo -e "${YELLOW}⚠️  Upload complete with errors${NC}"
  echo -e "   ${GREEN}✅ Successfully uploaded: $((UPLOADED - FAILED)) files${NC}"
  echo -e "   ${RED}❌ Failed: $FAILED files${NC}"
  echo ""
  echo -e "${YELLOW}Failed files:${NC}"
  cat "$ERROR_LOG"
fi

# Cleanup
rm -f "$ERROR_LOG"

# Provide next steps
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Check files: curl $API_URL/api/sessions/$SESSION_ID/files"
echo "  2. Run code:    curl -X POST $API_URL/api/sessions/$SESSION_ID/run -d '{\"code\": \"...\"}'"
echo "  3. View logs:   curl $API_URL/api/sessions/$SESSION_ID"

exit $FAILED
