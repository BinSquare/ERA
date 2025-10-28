# ERA Recipes System

A collection of ready-to-run code examples that demonstrate ERA Agent capabilities. Perfect for testing, stress testing, and learning.

## 🎯 What Are Recipes?

Recipes are self-contained, executable examples that:
- **Install dependencies automatically** (npm, pip packages)
- **Run in isolated VMs** (safe sandboxed execution)
- **Use environment variables** (via .env files)
- **Work locally and remotely** (same code, anywhere)
- **Include complete documentation** (README, examples, API docs)

## 🚀 Quick Start

```bash
# List all recipes
./run-recipe.sh --list

# Get detailed info
./run-recipe.sh --info groq-chat

# Run a recipe
./run-recipe.sh storage-demo

# Test all recipes
./tests/test-all-recipes.sh
```

## 📚 Available Recipes

| Recipe | Description | Language | API Key Required |
|--------|-------------|----------|------------------|
| **groq-chat** | Fast LLM inference with Groq | Node.js | Yes (GROQ_API_KEY) |
| **openai-chat** | GPT models for chat/generation | Node.js | Yes (OPENAI_API_KEY) |
| **ai-sdk-demo** | Vercel AI SDK with OpenAI | Node.js | Yes (OPENAI_API_KEY) |
| **storage-demo** | KV, D1, R2 storage operations | Python | No |
| **web-scraper** | Web content extraction | Python | No |

## 💡 Example Usage

### Running the Storage Demo

```bash
# No setup required - just run it!
./run-recipe.sh storage-demo
```

**Output:**
```
==================================================
🚀 ERA Storage Demo
==================================================

📦 KV Storage Demo
--------------------------------------------------
✅ Stored user data
👤 Retrieved user: Alice (alice@example.com)
📝 Found 3 items

🗄️  D1 Database Demo
--------------------------------------------------
✅ Created todos table
➕ Added 3 tasks
📋 Pending tasks:
  ○ Learn ERA Storage
  ○ Build something cool
  ○ Deploy to production
✅ Marked first task as complete

📁 R2 Object Storage Demo
--------------------------------------------------
✅ Stored hello.txt
📄 Found 3 log files
📖 File content:
Hello from ERA Storage!
Generated at: 2025-10-25T18:15:30

✨ Demo completed successfully!
```

### Running with API Keys

```bash
# 1. Copy environment template
cp recipes/groq-chat/.env.example recipes/groq-chat/.env

# 2. Edit with your API key
# GROQ_API_KEY=gsk_your_key_here

# 3. Run the recipe
./run-recipe.sh groq-chat
```

**Output:**
```
🚀 Calling Groq API...

✨ Response:
Fast language models are crucial because they enable real-time AI
applications that were previously impossible. They reduce latency in
chatbots, code assistants, and other interactive tools.

📊 Model: llama-3.3-70b-versatile
⚡ Tokens: 48

✓ Recipe completed successfully
Duration: 2847ms
```

## 🧪 Testing & Stress Testing

### Test All Recipes

```bash
./tests/test-all-recipes.sh
```

**Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ERA Recipe Test Suite
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

API URL: http://localhost:8787
Results: ./recipe-results

[1] Testing: groq-chat
  ⊘ Skipped (Missing required env: GROQ_API_KEY)

[2] Testing: openai-chat
  ⊘ Skipped (Missing required env: OPENAI_API_KEY)

[3] Testing: storage-demo
  ✓ Passed (3421ms)

[4] Testing: web-scraper
  ✓ Passed (4156ms)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Test Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Total Recipes: 4
Passed: 2
Failed: 0
Skipped: 2
Duration: 8s

Success Rate: 100.0%

All recipes passed!
```

### Parallel Stress Test

Run multiple recipes simultaneously to stress test:

```bash
# Run 10 storage demos in parallel
for i in {1..10}; do
  ./run-recipe.sh storage-demo &
done
wait

# Or test different recipes
./run-recipe.sh storage-demo &
./run-recipe.sh web-scraper &
./run-recipe.sh groq-chat &
wait
```

## 📁 Recipe Structure

Each recipe follows this structure:

```
recipe-name/
├── index.js|py          # Main executable code
├── recipe.json          # Metadata (language, deps, env vars)
├── .env.example         # Environment variable template
└── README.md            # Documentation
```

### recipe.json Example

```json
{
  "name": "groq-chat",
  "title": "Groq Chat API",
  "description": "Fast inference with Groq",
  "language": "node",
  "entrypoint": "index.js",
  "dependencies": {
    "npm": ["openai"]
  },
  "env_required": ["GROQ_API_KEY"],
  "env_optional": ["PROMPT", "MODEL"],
  "estimated_runtime": "2-5s"
}
```

## 🛠️ Creating Your Own Recipe

### 1. Create Directory

```bash
mkdir recipes/my-recipe
cd recipes/my-recipe
```

### 2. Write Code

```python
# index.py
import os

def main():
    name = os.getenv('NAME', 'World')
    message = os.getenv('MESSAGE', 'Hello')
    print(f"{message}, {name}!")

if __name__ == "__main__":
    main()
```

### 3. Create Metadata

```json
{
  "name": "my-recipe",
  "title": "My Greeting Recipe",
  "description": "A customizable greeting",
  "language": "python",
  "entrypoint": "index.py",
  "dependencies": {},
  "env_optional": ["NAME", "MESSAGE"],
  "estimated_runtime": "1s"
}
```

### 4. Add Environment Template

```bash
# .env.example
NAME=World
MESSAGE=Hello
```

### 5. Test It

```bash
../../run-recipe.sh my-recipe
```

## 🌐 Running Remotely

### Use Hosted ERA Agent

```bash
# Set remote URL
export ERA_API_URL=https://era-agent.yawnxyz.workers.dev

# Run recipe on hosted worker
./run-recipe.sh --remote storage-demo
```

### Switch Between Local and Remote

```bash
# Local (default)
./run-recipe.sh storage-demo

# Remote
ERA_API_URL=https://era-agent.yawnxyz.workers.dev \
  ./run-recipe.sh storage-demo
```

## 📊 Monitoring & Debugging

### Check Session Status

```bash
# List active sessions
curl http://localhost:8787/api/sessions | jq '.'

# Get session details
curl http://localhost:8787/api/sessions/recipe-123 | jq '.'
```

### View Storage Usage

```bash
# Get statistics
curl http://localhost:8787/api/resources/stats | jq '.'

# List all resources
curl http://localhost:8787/api/resources/list | jq '.'
```

### Debug Recipe Execution

```bash
# Run with verbose output
./run-recipe.sh storage-demo 2>&1 | tee debug.log

# Check recipe logs
ls -la recipe-results/
cat recipe-results/storage-demo.json
```

## 🎓 Use Cases

### 1. Learning ERA Agent

Start with simple recipes to understand ERA's capabilities:
```bash
./run-recipe.sh --info storage-demo
./run-recipe.sh storage-demo
```

### 2. Testing New Features

Create a recipe to test a new feature before integrating:
```bash
cp -r recipes/storage-demo recipes/my-feature-test
# Edit my-feature-test/index.py
./run-recipe.sh my-feature-test
```

### 3. Stress Testing

Run recipes in parallel to test system limits:
```bash
# 50 concurrent executions
for i in {1..50}; do
  ./run-recipe.sh storage-demo &
done
wait
```

### 4. Integration Testing

Use recipes in CI/CD pipelines:
```yaml
# .github/workflows/test.yml
- name: Test ERA Recipes
  run: |
    ./tests/test-all-recipes.sh
```

### 5. API Examples

Provide working examples for API documentation:
```bash
# Generate API usage examples
./run-recipe.sh groq-chat
./run-recipe.sh openai-chat
```

## 🔧 Advanced Usage

### Custom Environment Files

```bash
# Create custom config
cat > my-groq.env << EOF
GROQ_API_KEY=gsk_my_key
MODEL=mixtral-8x7b-32768
TEMPERATURE=0.5
PROMPT=Write a technical blog post introduction
EOF

# Run with custom env
./run-recipe.sh --env my-groq.env groq-chat
```

### Programmatic Execution

```javascript
// run-recipe.js
const { execSync } = require('child_process');

const recipes = ['storage-demo', 'web-scraper'];

recipes.forEach(recipe => {
  console.log(`Running ${recipe}...`);
  execSync(`./run-recipe.sh ${recipe}`, { stdio: 'inherit' });
});
```

### Continuous Testing

```bash
# Run tests every hour
watch -n 3600 './tests/test-all-recipes.sh'

# Or use cron
0 * * * * cd /path/to/cloudflare && ./tests/test-all-recipes.sh
```

## 📖 Next Steps

1. **Try all recipes**: `./tests/test-all-recipes.sh`
2. **Create your own**: See "Creating Your Own Recipe" above
3. **Contribute**: Submit a PR with your recipe
4. **Learn more**: Check out [ERA Documentation](./site/src/content/docs/)

## 🤝 Contributing

We welcome recipe contributions! See [recipes/README.md](./recipes/README.md) for guidelines.

## 📚 Learn More

- [Storage Proxy Guide](./site/src/content/docs/docs/guides/storage-proxy.mdx)
- [API Reference](./site/src/content/docs/docs/api-reference.mdx)
- [Recipe Development Guide](./recipes/README.md)
