# Groq Chat API Recipe

Fast LLM inference using Groq's optimized infrastructure with open-source models.

## What This Does

This recipe demonstrates how to use Groq's API for ultra-fast LLM inference. Groq specializes in hardware-accelerated inference, making it ideal for real-time applications.

## Setup

1. Get your Groq API key from [console.groq.com](https://console.groq.com/)
2. Copy `.env.example` to `.env` and add your key
3. Run the recipe!

## Environment Variables

- `GROQ_API_KEY` (required) - Your Groq API key
- `PROMPT` (optional) - Custom prompt to send
- `MODEL` (optional) - Model to use (default: llama-3.3-70b-versatile)
- `TEMPERATURE` (optional) - Temperature 0-2 (default: 0.7)
- `MAX_TOKENS` (optional) - Max response tokens (default: 150)

## Available Models

- `llama-3.3-70b-versatile` - Best for general tasks
- `mixtral-8x7b-32768` - Good for long context
- `gemma2-9b-it` - Faster, smaller model

## Example Output

```
🚀 Calling Groq API...

✨ Response:
Fast language models are crucial because they enable real-time AI applications
that were previously impossible. They reduce latency in chatbots, code assistants,
and other interactive tools, making AI more practical and accessible.

📊 Model: llama-3.3-70b-versatile
⚡ Tokens: 48
```

## Learn More

- [Groq Documentation](https://console.groq.com/docs)
- [Supported Models](https://console.groq.com/docs/models)
