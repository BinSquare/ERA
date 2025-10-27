#!/bin/bash
# ERA Recipe Test Suite
# Run all recipes to test/stress test the system

set -e

# Configuration
API_URL="${ERA_API_URL:-http://localhost:8787}"
RECIPES_DIR="$(dirname "$0")/../recipes"
RESULTS_DIR="$(dirname "$0")/recipe-results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create results directory
mkdir -p "$RESULTS_DIR"

# Stats
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# Start time
START_TIME=$(date +%s)

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  ERA Recipe Test Suite${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "API URL: ${YELLOW}$API_URL${NC}"
echo -e "Results: ${YELLOW}$RESULTS_DIR${NC}"
echo ""

# Test a single recipe
test_recipe() {
    local recipe_name="$1"
    local recipe_dir="$RECIPES_DIR/$recipe_name"
    local recipe_file="$recipe_dir/recipe.json"
    local result_file="$RESULTS_DIR/$recipe_name.json"

    TOTAL=$((TOTAL + 1))

    echo -e "${BLUE}[$TOTAL] Testing:${NC} $recipe_name"

    # Check if recipe has required env vars
    local env_required=$(jq -r '.env_required // []' "$recipe_file")
    local has_required_env=true

    while IFS= read -r var; do
        if [ -n "$var" ] && [ "$var" != "null" ]; then
            if [ -z "${!var}" ]; then
                has_required_env=false
                echo -e "  ${YELLOW}⊘ Skipped${NC} (Missing required env: $var)"
                SKIPPED=$((SKIPPED + 1))
                return
            fi
        fi
    done < <(echo "$env_required" | jq -r '.[]')

    # Run the recipe
    local start=$(date +%s%3N)

    if timeout 60 "$RECIPES_DIR/../run-recipe.sh" "$recipe_name" > "$result_file.log" 2>&1; then
        local end=$(date +%s%3N)
        local duration=$((end - start))

        echo -e "  ${GREEN}✓ Passed${NC} (${duration}ms)"
        PASSED=$((PASSED + 1))

        # Save result
        echo "{\"recipe\": \"$recipe_name\", \"status\": \"passed\", \"duration_ms\": $duration, \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "$result_file"
    else
        local end=$(date +%s%3N)
        local duration=$((end - start))

        echo -e "  ${RED}✗ Failed${NC} (${duration}ms)"
        FAILED=$((FAILED + 1))

        # Save result
        echo "{\"recipe\": \"$recipe_name\", \"status\": \"failed\", \"duration_ms\": $duration, \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "$result_file"

        # Show error log
        echo -e "  ${RED}Error log:${NC}"
        tail -20 "$result_file.log" | sed 's/^/    /'
    fi

    echo ""
}

# Find all recipes
for recipe_dir in "$RECIPES_DIR"/*; do
    if [ -d "$recipe_dir" ]; then
        recipe_name=$(basename "$recipe_dir")
        recipe_file="$recipe_dir/recipe.json"

        if [ -f "$recipe_file" ]; then
            test_recipe "$recipe_name"
        fi
    fi
done

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Total Recipes: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Skipped: $SKIPPED${NC}"
echo -e "Duration: ${DURATION}s"
echo ""

# Generate summary JSON
jq -s '.' "$RESULTS_DIR"/*.json > "$RESULTS_DIR/summary.json" 2>/dev/null || true

# Success rate
if [ $TOTAL -gt 0 ]; then
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($PASSED / $TOTAL) * 100}")
    echo -e "Success Rate: ${SUCCESS_RATE}%"
fi

echo ""

# Exit with error if any tests failed
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Some recipes failed${NC}"
    exit 1
else
    echo -e "${GREEN}All recipes passed!${NC}"
    exit 0
fi
