# AI SDK Demo Recipe

Demonstrates using the [Vercel AI SDK](https://sdk.vercel.ai/) with OpenAI for text generation. This recipe shows the modern, type-safe approach to working with LLMs.

## What This Recipe Does

- ✅ Uses `@ai-sdk/openai` and `ai` packages
- ✅ Demonstrates `generateText` function
- ✅ Supports all OpenAI models (GPT-4o, GPT-5, o1, etc.)
- ✅ Shows usage metadata (tokens, duration)
- ✅ Handles errors gracefully
- ✅ Configurable via environment variables

## Setup

1. **Get an OpenAI API Key**
   - Sign up at [OpenAI Platform](https://platform.openai.com/)
   - Create an API key in your dashboard

2. **Configure Environment**
   ```bash
   cd recipes/ai-sdk-demo
   cp .env.example .env
   # Edit .env and add your OPENAI_API_KEY
   ```

3. **Run the Recipe**
   ```bash
   ../../run-recipe.sh ai-sdk-demo
   ```

## Configuration

### Required
- `OPENAI_API_KEY` - Your OpenAI API key

### Optional
- `PROMPT` - The text prompt to send (default: about fast language models)
- `MODEL` - Which model to use (default: `gpt-4o-mini`)
- `TEMPERATURE` - Creativity level 0-2 (default: `0.7`)
- `MAX_TOKENS` - Maximum response length (default: `500`)

## Example Output

```
==================================================
🤖 AI SDK Demo with OpenAI
==================================================

📋 Configuration:
   Model: gpt-4o-mini
   Temperature: 0.7
   Max Tokens: 500
   Prompt: "Explain the importance of fast language models in 3 sentences."

⏳ Generating response...

✨ Response:
--------------------------------------------------
Fast language models are crucial because they enable real-time
AI applications like chatbots and coding assistants. They reduce
latency, making interactions feel natural and responsive. This
speed unlocks new use cases in customer service, education, and
creative tools.
--------------------------------------------------

📊 Metadata:
   Completion Tokens: 48
   Prompt Tokens: 18
   Total Tokens: 66
   Duration: 1247ms
   Finish Reason: stop

✅ Generation completed successfully!
```

## Available Models

### Production Models
- **gpt-4o** - Most capable, multimodal (text + images)
- **gpt-4o-mini** - Fast and affordable, great for most tasks
- **gpt-5** - Latest generation, most advanced
- **gpt-5-mini** - Fast GPT-5 variant
- **gpt-5-nano** - Ultra-fast, lightweight

### Reasoning Models
- **o1** - Advanced reasoning, complex problems
- **o1-mini** - Faster reasoning variant
- **o3** - Next-gen reasoning
- **o4-mini** - Latest fast reasoning model

## Advanced Examples

### Using Reasoning Models

```bash
# Set environment for o1 reasoning model
export MODEL=o1-mini
export PROMPT="Solve this: If a train leaves Station A at 60mph..."

../../run-recipe.sh ai-sdk-demo
```

### Creative Writing

```bash
# Higher temperature for creativity
export MODEL=gpt-4o
export TEMPERATURE=1.2
export MAX_TOKENS=1000
export PROMPT="Write a short story about a robot learning to paint"

../../run-recipe.sh ai-sdk-demo
```

### Technical Explanations

```bash
# Lower temperature for focused responses
export MODEL=gpt-5-mini
export TEMPERATURE=0.2
export PROMPT="Explain how async/await works in JavaScript"

../../run-recipe.sh ai-sdk-demo
```

## Why AI SDK?

The Vercel AI SDK provides several advantages:

1. **Type Safety** - Full TypeScript support
2. **Unified API** - Works with OpenAI, Anthropic, Google, etc.
3. **Streaming** - Built-in support for streaming responses
4. **Tool Calling** - Easy function calling / tool usage
5. **Structured Output** - Generate JSON objects with schemas
6. **Modern** - Built for React Server Components, Next.js, etc.

## Comparison with OpenAI Client

### This Recipe (AI SDK)
```javascript
import { openai } from '@ai-sdk/openai';
import { generateText } from 'ai';

const result = await generateText({
  model: openai('gpt-4o-mini'),
  prompt: 'Hello!'
});
```

### Alternative (OpenAI Client)
```javascript
import OpenAI from 'openai';

const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const result = await client.chat.completions.create({
  model: 'gpt-4o-mini',
  messages: [{ role: 'user', content: 'Hello!' }]
});
```

Both work, but AI SDK provides:
- Simpler API for common tasks
- Better TypeScript support
- Multi-provider support
- Built-in streaming utilities

## Next Steps

- Try different models and prompts
- Explore streaming with `streamText`
- Generate structured JSON with `generateObject`
- Add tool calling / function execution
- Build a chatbot with conversation history

## Learn More

- [AI SDK Documentation](https://sdk.vercel.ai/docs)
- [OpenAI Models](https://platform.openai.com/docs/models)
- [AI SDK Examples](https://sdk.vercel.ai/examples)
- [ERA Agent Recipes](../../RECIPES.md)
