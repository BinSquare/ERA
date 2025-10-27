#!/bin/bash
# ERA Recipe Runner
# Executes recipes on local or hosted ERA Agent

set -e

# Configuration
API_URL="${ERA_API_URL:-http://localhost:8787}"
RECIPES_DIR="$(dirname "$0")/recipes"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help function
show_help() {
    cat << EOF
ERA Recipe Runner

Usage: $0 [OPTIONS] <recipe-name>

Execute a recipe in local ERA Agent environment.

NOTE: Recipes require local ERA Agent due to package installation requirements.
      Start local agent with: cd era-agent && go run .

OPTIONS:
    -e, --env FILE      Use specific .env file (default: recipe/.env)
    --list              List all available recipes
    --info RECIPE       Show information about a recipe
    -h, --help          Show this help message

EXAMPLES:
    # List all recipes
    $0 --list

    # Get info about a recipe
    $0 --info groq-chat

    # Run a recipe
    $0 groq-chat

    # Run with custom env file
    $0 --env my-groq.env groq-chat

ENVIRONMENT:
    ERA_API_URL         API endpoint (default: http://localhost:8787)

EOF
}

# List recipes
list_recipes() {
    echo -e "${BLUE}Available Recipes:${NC}"
    echo ""

    for recipe_dir in "$RECIPES_DIR"/*; do
        if [ -d "$recipe_dir" ]; then
            recipe_name=$(basename "$recipe_dir")
            recipe_file="$recipe_dir/recipe.json"

            if [ -f "$recipe_file" ]; then
                title=$(jq -r '.title // .name' "$recipe_file")
                desc=$(jq -r '.description' "$recipe_file")
                tags=$(jq -r '.tags | join(", ")' "$recipe_file")

                echo -e "${GREEN}$recipe_name${NC} - $title"
                echo "  $desc"
                echo -e "  Tags: ${YELLOW}$tags${NC}"
                echo ""
            fi
        fi
    done
}

# Show recipe info
show_info() {
    local recipe_name="$1"
    local recipe_dir="$RECIPES_DIR/$recipe_name"
    local recipe_file="$recipe_dir/recipe.json"

    if [ ! -f "$recipe_file" ]; then
        echo -e "${RED}Error: Recipe '$recipe_name' not found${NC}"
        exit 1
    fi

    echo -e "${BLUE}Recipe Information:${NC}"
    echo ""
    jq -r '
        "Name: " + .name + "\n" +
        "Title: " + .title + "\n" +
        "Description: " + .description + "\n" +
        "Language: " + .language + "\n" +
        "Entrypoint: " + .entrypoint + "\n" +
        "Tags: " + (.tags | join(", ")) + "\n" +
        "Estimated Runtime: " + .estimated_runtime + "\n" +
        "Required Env Vars: " + (if .env_required | length > 0 then (.env_required | join(", ")) else "None" end) + "\n" +
        "Optional Env Vars: " + (if .env_optional | length > 0 then (.env_optional | join(", ")) else "None" end)
    ' "$recipe_file"

    if [ -f "$recipe_dir/README.md" ]; then
        echo ""
        echo -e "${BLUE}README:${NC}"
        head -20 "$recipe_dir/README.md"
    fi
}

# Load .env file
load_env() {
    local env_file="$1"

    if [ -f "$env_file" ]; then
        echo -e "${YELLOW}Loading environment from: $env_file${NC}"
        set -a
        source "$env_file"
        set +a
    fi
}

# Run recipe
run_recipe() {
    local recipe_name="$1"
    local recipe_dir="$RECIPES_DIR/$recipe_name"
    local recipe_file="$recipe_dir/recipe.json"

    if [ ! -f "$recipe_file" ]; then
        echo -e "${RED}Error: Recipe '$recipe_name' not found${NC}"
        exit 1
    fi

    # Parse recipe metadata
    local language=$(jq -r '.language' "$recipe_file")
    local entrypoint=$(jq -r '.entrypoint' "$recipe_file")
    local npm_deps=$(jq -r '.dependencies.npm // [] | join(" ")' "$recipe_file")
    local pip_deps=$(jq -r '.dependencies.pip // [] | join(" ")' "$recipe_file")

    echo -e "${BLUE}Running recipe: ${GREEN}$recipe_name${NC}"
    echo ""

    # Check if API is available
    echo -e "${YELLOW}Checking API availability...${NC}"
    # Check sessions endpoint to verify API is accessible
    if ! curl -sf "$API_URL/api/sessions" > /dev/null 2>&1; then
        echo -e "${RED}Error: Cannot connect to ERA Agent at $API_URL${NC}"
        echo -e "${YELLOW}Hint: Start the local ERA Agent with:${NC}"
        echo -e "  ${BLUE}cd era-agent && go run .${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} API is available"
    echo ""

    # Read the code
    local code_file="$recipe_dir/$entrypoint"
    if [ ! -f "$code_file" ]; then
        echo -e "${RED}Error: Entrypoint '$entrypoint' not found${NC}"
        exit 1
    fi

    local code=$(cat "$code_file")

    # Build setup config
    local setup_json="{}"
    if [ -n "$npm_deps" ]; then
        setup_json=$(echo "$setup_json" | jq --arg deps "$npm_deps" '. + {npm: ($deps | split(" "))}')
    fi
    if [ -n "$pip_deps" ]; then
        setup_json=$(echo "$setup_json" | jq --arg deps "$pip_deps" '. + {pip: ($deps | split(" "))}')
    fi

    # Build env vars JSON
    local env_json="{}"
    local env_required=$(jq -r '.env_required // []' "$recipe_file")
    local env_optional=$(jq -r '.env_optional // []' "$recipe_file")

    # Check required env vars
    while IFS= read -r var; do
        if [ -n "$var" ] && [ "$var" != "null" ]; then
            if [ -z "${!var}" ]; then
                echo -e "${RED}Error: Required environment variable $var is not set${NC}"
                echo -e "${YELLOW}Hint: Copy $recipe_dir/.env.example to .env and fill in values${NC}"
                exit 1
            fi
            env_json=$(echo "$env_json" | jq --arg key "$var" --arg val "${!var}" '. + {($key): $val}')
        fi
    done < <(echo "$env_required" | jq -r '.[]')

    # Add optional env vars if set
    while IFS= read -r var; do
        if [ -n "$var" ] && [ "$var" != "null" ] && [ -n "${!var}" ]; then
            env_json=$(echo "$env_json" | jq --arg key "$var" --arg val "${!var}" '. + {($key): $val}')
        fi
    done < <(echo "$env_optional" | jq -r '.[]')

    # Create session
    echo -e "${YELLOW}Creating session...${NC}"
    local session_id="recipe-$(date +%s)-$RANDOM"

    local create_payload=$(jq -n \
        --arg lang "$language" \
        --arg sid "$session_id" \
        --argjson setup "$setup_json" \
        '{language: $lang, session_id: $sid, persistent: false, setup: $setup}')

    local create_response=$(curl -s -X POST "$API_URL/api/sessions" \
        -H "Content-Type: application/json" \
        -d "$create_payload")

    if [ $? -ne 0 ] || echo "$create_response" | grep -q "error"; then
        echo -e "${RED}✗${NC} Failed to create session"
        echo "$create_response" | jq -r '.error // .'
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Session created: $session_id"

    # Wait for setup if needed
    if [ "$npm_deps" != "" ] || [ "$pip_deps" != "" ]; then
        echo -e "${YELLOW}Installing dependencies...${NC}"
        local max_wait=300  # 5 minutes timeout
        local elapsed=0
        while true; do
            status=$(curl -s "$API_URL/api/sessions/$session_id" | jq -r '.setup_status // "completed"')
            if [ "$status" = "completed" ]; then
                echo -e "${GREEN}✓${NC} Dependencies installed"
                break
            elif [ "$status" = "failed" ]; then
                echo -e "${RED}✗${NC} Dependency installation failed"
                exit 1
            elif [ $elapsed -ge $max_wait ]; then
                echo -e "${RED}✗${NC} Setup timeout (${max_wait}s)"
                exit 1
            fi
            sleep 2
            elapsed=$((elapsed + 2))
            if [ $((elapsed % 10)) -eq 0 ]; then
                echo -e "  Still installing... (${elapsed}s elapsed)"
            fi
        done
    fi

    # Run the code
    echo -e "${YELLOW}Executing recipe...${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local run_payload=$(jq -n \
        --arg code "$code" \
        --argjson env "$env_json" \
        '{code: $code, env: $env}')

    local result=$(curl -s -X POST "$API_URL/api/sessions/$session_id/run" \
        -H "Content-Type: application/json" \
        -d "$run_payload")

    # Output results
    echo "$result" | jq -r '.stdout'
    local stderr=$(echo "$result" | jq -r '.stderr // ""')
    if [ -n "$stderr" ]; then
        echo -e "${RED}$stderr${NC}"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Show execution stats
    local exit_code=$(echo "$result" | jq -r '.exit_code')
    local duration=$(echo "$result" | jq -r '.execution_time_ms // 0')

    if [ "$exit_code" = "0" ]; then
        echo -e "${GREEN}✓ Recipe completed successfully${NC}"
    else
        echo -e "${RED}✗ Recipe failed with exit code $exit_code${NC}"
    fi

    echo -e "Duration: ${duration}ms"
}

# Parse arguments
ENV_FILE=""
RECIPE_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            ENV_FILE="$2"
            shift 2
            ;;
        --list)
            list_recipes
            exit 0
            ;;
        --info)
            show_info "$2"
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            RECIPE_NAME="$1"
            shift
            ;;
    esac
done

# Check if recipe name provided
if [ -z "$RECIPE_NAME" ]; then
    echo -e "${RED}Error: No recipe specified${NC}"
    echo ""
    show_help
    exit 1
fi

# Load environment
if [ -n "$ENV_FILE" ]; then
    load_env "$ENV_FILE"
elif [ -f "$RECIPES_DIR/$RECIPE_NAME/.env" ]; then
    load_env "$RECIPES_DIR/$RECIPE_NAME/.env"
fi

# Run the recipe
run_recipe "$RECIPE_NAME"
