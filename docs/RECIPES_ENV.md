# Recipe Environment Variables Guide

How to manage API keys and environment variables for ERA recipes in different deployment scenarios.

## 🎯 Quick Answer

**Current Setup (Recipe Runner Script):** You **don't need** to add secrets to your Cloudflare Worker. The `run-recipe.sh` script passes environment variables directly to the sandboxed code via API requests.

**Future Setup (Worker-side Recipe Execution):** If you want to run recipes from within your Worker code, use Cloudflare Secrets.

---

## 📋 Current Architecture

### How Recipes Use Environment Variables

```bash
# 1. You set environment variables locally
cp recipes/groq-chat/.env.example recipes/groq-chat/.env
# Edit .env with your GROQ_API_KEY

# 2. run-recipe.sh loads the .env file
./run-recipe.sh groq-chat

# 3. Script sends env vars in API request body
curl -X POST https://anewera.dev/api/sessions/{id}/run \
  -d '{"code": "...", "env": {"GROQ_API_KEY": "gsk_..."}}'

# 4. Worker passes env vars to sandboxed VM
# 5. Recipe code accesses: process.env.GROQ_API_KEY
```

**Key Point:** The Worker doesn't need access to these secrets - they're passed through in the request body and set in the VM environment.

---

## 🔧 Option 1: Local Development (Current)

### Using Recipe .env Files

**Best for:** Running recipes via `run-recipe.sh` locally or remotely

```bash
# 1. Copy the example
cp recipes/groq-chat/.env.example recipes/groq-chat/.env

# 2. Add your API key
echo "GROQ_API_KEY=gsk_your_actual_key_here" > recipes/groq-chat/.env

# 3. Run the recipe (works locally or remote)
./run-recipe.sh groq-chat

# Or against hosted worker
ERA_API_URL=https://anewera.dev ./run-recipe.sh groq-chat
```

**Pros:**
- ✅ No Worker configuration needed
- ✅ Works with both local and hosted workers
- ✅ Each recipe has its own .env file
- ✅ Easy to manage multiple API keys

**Cons:**
- ❌ Requires local .env files
- ❌ Can't run recipes directly from browser/Worker code

---

## 🚀 Option 2: Cloudflare Secrets (Production)

### If You Want to Run Recipes Server-Side

**Best for:** Building a web UI or API that runs recipes server-side

### Step 1: Add Secrets to Cloudflare

```bash
# Add secrets to your deployed worker
wrangler secret put GROQ_API_KEY
# Enter your key when prompted: gsk_...

wrangler secret put OPENAI_API_KEY
# Enter your key when prompted: sk-...
```

### Step 2: Access Secrets in Worker Code

```typescript
// src/index.ts or wherever you handle requests
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Secrets are available in env
    const groqKey = env.GROQ_API_KEY;
    const openaiKey = env.OPENAI_API_KEY;

    // Pass to recipe execution
    const recipeEnv = {
      GROQ_API_KEY: groqKey,
      MODEL: "llama-3.3-70b-versatile"
    };

    // Execute recipe with these env vars
    const response = await fetch(`${ERA_AGENT_URL}/api/sessions/${sessionId}/run`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        code: recipeCode,
        env: recipeEnv
      })
    });

    return response;
  }
};
```

### Step 3: Update TypeScript Types

```typescript
// src/types.ts or in your worker file
interface Env {
  ERA_AGENT: DurableObjectNamespace;
  SESSIONS: DurableObjectNamespace;
  STORAGE_REGISTRY: DurableObjectNamespace;
  ERA_KV: KVNamespace;
  ERA_D1: D1Database;
  ERA_R2: R2Bucket;

  // Add your secrets
  GROQ_API_KEY?: string;
  OPENAI_API_KEY?: string;
}
```

**Pros:**
- ✅ Secrets encrypted in Cloudflare
- ✅ Can run recipes from Worker code
- ✅ No local .env files needed
- ✅ Centralized secret management

**Cons:**
- ❌ Requires wrangler CLI access
- ❌ Secrets shared across all recipes
- ❌ More complex setup

---

## 🧪 Option 3: Local Development with Wrangler

### Using .dev.vars for Local Worker Development

**Best for:** Developing Worker code that runs recipes server-side

```bash
# 1. Copy the example
cp .dev.vars.example .dev.vars

# 2. Add your keys
cat >> .dev.vars << EOF
GROQ_API_KEY=gsk_your_key_here
OPENAI_API_KEY=sk_your_key_here
EOF

# 3. Run worker locally
wrangler dev

# Now env.GROQ_API_KEY is available in your worker code
```

**File:** `.dev.vars`
```bash
# Local development only - NOT committed to git
GROQ_API_KEY=gsk_your_api_key_here
OPENAI_API_KEY=sk_your_api_key_here
MODEL=llama-3.3-70b-versatile
```

**Pros:**
- ✅ Works with `wrangler dev`
- ✅ Simulates production secrets locally
- ✅ Not committed to git

**Cons:**
- ❌ Only for local development
- ❌ Still need to set production secrets separately

---

## 🎨 Option 4: Non-Secret Variables in wrangler.toml

### For Non-Sensitive Configuration

**Best for:** Default values, public configuration

```toml
# wrangler.toml
[vars]
DEFAULT_MODEL = "llama-3.3-70b-versatile"
DEFAULT_TEMPERATURE = "0.7"
DEFAULT_MAX_TOKENS = "150"
```

Access in Worker:
```typescript
const model = env.DEFAULT_MODEL;
```

**⚠️ Warning:** Do NOT put API keys in `[vars]` - they'll be visible in your deployed code!

---

## 🔐 Security Best Practices

### ✅ DO:
- Use `.env` files for local recipe execution
- Use `wrangler secret put` for production API keys
- Use `.dev.vars` for local worker development
- Keep secrets in `.gitignore`

### ❌ DON'T:
- Commit `.env` or `.dev.vars` files
- Put API keys in `wrangler.toml` `[vars]`
- Hardcode secrets in your code
- Share secrets in documentation

---

## 📊 Comparison Table

| Method | Use Case | Security | Setup Complexity |
|--------|----------|----------|------------------|
| **Recipe .env** | Running recipes locally/remotely | ⭐⭐⭐ Local only | ⭐ Easy |
| **Wrangler Secrets** | Server-side recipe execution | ⭐⭐⭐⭐⭐ Encrypted | ⭐⭐⭐ Moderate |
| **.dev.vars** | Local worker development | ⭐⭐⭐ Local only | ⭐⭐ Easy |
| **wrangler.toml [vars]** | Public configuration | ⭐ Not secure | ⭐ Easy |

---

## 🎯 Recommended Setup

### For Most Users (Current):

```bash
# 1. Create recipe .env files
cp recipes/groq-chat/.env.example recipes/groq-chat/.env
# Add your keys

# 2. Run recipes
./run-recipe.sh groq-chat
```

### For Building a Web UI:

```bash
# 1. Local development
cp .dev.vars.example .dev.vars
# Add your keys
wrangler dev

# 2. Production
wrangler secret put GROQ_API_KEY
wrangler secret put OPENAI_API_KEY
wrangler deploy

# 3. Access in Worker code
const groqKey = env.GROQ_API_KEY;
```

---

## 📖 Examples

### Example 1: Running Recipe with Local .env

```bash
# recipes/groq-chat/.env
GROQ_API_KEY=gsk_abc123
PROMPT=Write a haiku about coding
MODEL=mixtral-8x7b-32768

# Run it
./run-recipe.sh groq-chat
```

### Example 2: Building a Recipe API Endpoint

```typescript
// src/recipe-runner.ts
export async function runRecipe(
  recipeName: string,
  env: Env
): Promise<Response> {
  // Get secrets from Worker env
  const secrets = {
    GROQ_API_KEY: env.GROQ_API_KEY,
    OPENAI_API_KEY: env.OPENAI_API_KEY,
  };

  // Load recipe code
  const recipe = await loadRecipe(recipeName);

  // Create session
  const session = await createSession(env);

  // Run with secrets
  const result = await session.run({
    code: recipe.code,
    env: secrets
  });

  return new Response(JSON.stringify(result));
}
```

### Example 3: Recipe Selection API

```typescript
// Allow users to run recipes via API
app.post('/api/run-recipe/:name', async (c) => {
  const recipeName = c.req.param('name');
  const userInput = await c.req.json();

  // Merge user input with server secrets
  const env = {
    ...userInput.env, // User-provided non-secret vars
    GROQ_API_KEY: c.env.GROQ_API_KEY, // Server secret
    OPENAI_API_KEY: c.env.OPENAI_API_KEY, // Server secret
  };

  return runRecipe(recipeName, env);
});
```

---

## 🤔 FAQ

### Q: Do I need to add secrets to my Worker?
**A:** Not if you're using `run-recipe.sh` - it passes env vars in the API request.

### Q: Can I use .env with wrangler?
**A:** Use `.dev.vars` for local dev, `wrangler secret put` for production.

### Q: Are my secrets safe?
**A:** Yes - `.env` and `.dev.vars` are gitignored. Production secrets are encrypted by Cloudflare.

### Q: Can I run recipes without local .env files?
**A:** Yes - pass env vars directly:
```bash
GROQ_API_KEY=gsk_... ./run-recipe.sh groq-chat
```

### Q: What if I want different keys for different recipes?
**A:** Each recipe can have its own `.env` file in `recipes/{name}/.env`

---

## 📚 Learn More

- [Cloudflare Secrets Documentation](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Wrangler CLI Reference](https://developers.cloudflare.com/workers/wrangler/)
- [Recipe System Guide](./RECIPES.md)
- [API Reference](./site/src/content/docs/docs/api-reference.mdx)
