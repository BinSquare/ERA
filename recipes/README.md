# ERA Recipes

Ready-to-run code examples demonstrating ERA Agent capabilities. Each recipe is a self-contained example that you can run immediately.

## Quick Start

```bash
# List all recipes
./run-recipe.sh --list

# Get info about a recipe
./run-recipe.sh --info groq-chat

# Run a recipe
./run-recipe.sh groq-chat

# Test all recipes
../tests/test-all-recipes.sh
```

## Available Recipes

### LLM & AI

#### **groq-chat**
Fast LLM inference using Groq's optimized infrastructure.
- Language: JavaScript (Node.js)
- Dependencies: openai
- Requires: GROQ_API_KEY

#### **openai-chat**
Use GPT models for conversational AI and text generation.
- Language: JavaScript (Node.js)
- Dependencies: openai
- Requires: OPENAI_API_KEY

#### **ai-sdk-demo**
Demonstrate Vercel AI SDK's generateText with OpenAI models.
- Language: JavaScript (Node.js)
- Dependencies: @ai-sdk/openai, ai
- Requires: OPENAI_API_KEY

### Storage & Data

#### **storage-demo**
Complete demonstration of ERA's KV, D1, and R2 storage.
- Language: Python
- Dependencies: None (uses era_storage SDK)
- Requires: No API keys needed

### Web & Data Processing

#### **web-scraper**
Fetch and parse web content with requests and BeautifulSoup.
- Language: Python
- Dependencies: requests, beautifulsoup4, lxml
- Requires: No API keys needed

## Recipe Structure

Each recipe contains:

```
recipe-name/
├── index.js|py       # Main code
├── recipe.json       # Metadata
├── .env.example      # Environment variable template
└── README.md         # Documentation
```

### recipe.json Format

```json
{
  "name": "recipe-name",
  "title": "Display Title",
  "description": "What this recipe does",
  "language": "python|node|deno|go",
  "entrypoint": "index.py",
  "env_file": ".env.example",
  "dependencies": {
    "npm": ["package1", "package2"],
    "pip": ["package1", "package2"]
  },
  "tags": ["tag1", "tag2"],
  "env_required": ["API_KEY"],
  "env_optional": ["OPTIONAL_VAR"],
  "estimated_runtime": "2-5s",
  "api_docs": "https://docs.example.com"
}
```

## Running Recipes

### Local Development

```bash
# Start local ERA Agent (terminal 1)
cd ../era-agent
./agent server

# Run a recipe (terminal 2)
cd cloudflare
./run-recipe.sh storage-demo
```

### Hosted/Remote

```bash
# Set your hosted ERA Agent URL
export ERA_API_URL=https://anewera.dev

# Run the recipe
./run-recipe.sh --remote groq-chat
```

### With Custom Environment

```bash
# Create your .env file
cd recipes/groq-chat
cp .env.example .env
# Edit .env with your values

# Run with your environment
../../run-recipe.sh groq-chat
```

## Creating New Recipes

1. **Create directory structure:**
   ```bash
   mkdir recipes/my-recipe
   cd recipes/my-recipe
   ```

2. **Create your code:**
   ```bash
   # Python example
   cat > index.py << 'EOF'
   #!/usr/bin/env python3
   import os

   def main():
       name = os.getenv('NAME', 'World')
       print(f"Hello, {name}!")

   if __name__ == "__main__":
       main()
   EOF
   ```

3. **Create recipe.json:**
   ```json
   {
     "name": "my-recipe",
     "title": "My Recipe",
     "description": "A simple greeting",
     "language": "python",
     "entrypoint": "index.py",
     "dependencies": {},
     "tags": ["example"],
     "env_required": [],
     "env_optional": ["NAME"],
     "estimated_runtime": "1s"
   }
   ```

4. **Create .env.example:**
   ```bash
   # My Recipe Configuration
   NAME=World
   ```

5. **Test it:**
   ```bash
   ../../run-recipe.sh my-recipe
   ```

## Testing & Stress Testing

### Test All Recipes

```bash
../tests/test-all-recipes.sh
```

This will:
- Run every recipe in the recipes/ directory
- Skip recipes with missing API keys
- Report success/failure for each
- Generate a results summary
- Calculate success rate

### Parallel Stress Test

```bash
# Run 10 recipes in parallel
for i in {1..10}; do
  ./run-recipe.sh storage-demo &
done
wait
```

### Continuous Testing

```bash
# Run tests every 5 minutes
watch -n 300 '../tests/test-all-recipes.sh'
```

## Recipe Categories

### 📚 Examples & Learning
- **storage-demo** - Complete storage operations guide
- **web-scraper** - Web scraping basics

### 🤖 AI & LLMs
- **groq-chat** - Fast inference with Groq
- **openai-chat** - OpenAI GPT models

### 🔜 Coming Soon
- **anthropic-claude** - Claude AI assistant
- **image-generation** - DALL-E / Stable Diffusion
- **pdf-processor** - Parse and extract PDF data
- **csv-analyzer** - Data analysis with pandas
- **email-sender** - Send emails via SMTP
- **github-stats** - Fetch GitHub repository stats

## Environment Variables

### Global Configuration

- `ERA_API_URL` - ERA Agent endpoint (default: http://localhost:8787)

### Recipe-Specific

Each recipe documents its own environment variables in:
- `recipe/.env.example` - Template with all variables
- `recipe/recipe.json` - Lists required vs optional variables
- `recipe/README.md` - Detailed explanations

## Tips & Best Practices

### 1. Use .env Files

Don't commit secrets! Always use .env files:
```bash
# Copy template
cp recipes/groq-chat/.env.example recipes/groq-chat/.env

# Edit with your values
vim recipes/groq-chat/.env

# Run recipe (automatically loads .env)
./run-recipe.sh groq-chat
```

### 2. Test Locally First

Always test recipes locally before running on hosted ERA Agent:
```bash
# Local test
./run-recipe.sh my-recipe

# If it works, try remote
ERA_API_URL=https://your-worker.dev ./run-recipe.sh my-recipe
```

### 3. Check Dependencies

Recipes with dependencies take longer on first run:
```bash
# First run: installs packages (5-30s)
./run-recipe.sh groq-chat

# Subsequent runs: uses cached packages (2-5s)
./run-recipe.sh groq-chat
```

### 4. Use Storage for Persistence

For data that needs to persist across runs:
```python
import era_storage

# Save results
era_storage.kv.set("myapp", "last_run", json.dumps(results))

# Load on next run
previous = era_storage.kv.get("myapp", "last_run")
```

### 5. Monitor Resource Usage

```bash
# Check storage usage
curl http://localhost:8787/api/resources/stats | jq '.'

# List all resources
curl http://localhost:8787/api/resources/list | jq '.'
```

## Troubleshooting

### Recipe Fails with "API key not found"

**Solution:** Copy `.env.example` to `.env` and add your key:
```bash
cd recipes/groq-chat
cp .env.example .env
# Edit .env with your API key
```

### Recipe Times Out

**Solution:** Increase timeout in the recipe:
```bash
# Default timeout is 30s
# Increase to 60s by editing recipe.json or passing in code
```

### Dependencies Won't Install

**Solution:** Check package names and availability:
```bash
# For npm packages
npm search package-name

# For pip packages
pip search package-name
```

### Can't Connect to ERA Agent

**Solution:** Make sure ERA Agent is running:
```bash
# Check if running
curl http://localhost:8787/api/health

# Start if not running
cd ../era-agent && ./agent server
```

## Contributing Recipes

We welcome recipe contributions! To add a new recipe:

1. Fork the repository
2. Create your recipe in `recipes/your-recipe-name/`
3. Include all required files (see Recipe Structure above)
4. Test thoroughly: `./run-recipe.sh your-recipe-name`
5. Add to test suite: `../tests/test-all-recipes.sh`
6. Submit a pull request

### Recipe Guidelines

- **Self-contained**: Include all necessary code and config
- **Documented**: Clear README with setup instructions
- **Tested**: Must pass local and hosted testing
- **Secure**: No hardcoded secrets or API keys
- **Tagged**: Use relevant tags for discoverability

## Learn More

- [ERA Agent Documentation](../site/src/content/docs/)
- [Storage Proxy Guide](../site/src/content/docs/docs/guides/storage-proxy.mdx)
- [API Reference](../site/src/content/docs/docs/api-reference.mdx)
