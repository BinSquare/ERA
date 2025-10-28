#!/usr/bin/env node
/**
 * AI SDK Demo Recipe
 * Demonstrates using the Vercel AI SDK with OpenAI
 */

import { openai } from '@ai-sdk/openai';
import { generateText } from 'ai';

async function main() {
  // Get configuration from environment variables
  const apiKey = process.env.OPENAI_API_KEY;
  const prompt = process.env.PROMPT || 'Explain the importance of fast language models in 3 sentences.';
  const model = process.env.MODEL || 'gpt-4o-mini';
  const temperature = parseFloat(process.env.TEMPERATURE || '0.7');
  const maxTokens = parseInt(process.env.MAX_TOKENS || '500');

  // Validate API key
  if (!apiKey) {
    console.error('❌ Error: OPENAI_API_KEY environment variable is required');
    process.exit(1);
  }

  console.log('==================================================');
  console.log('🤖 AI SDK Demo with OpenAI');
  console.log('==================================================\n');

  console.log('📋 Configuration:');
  console.log(`   Model: ${model}`);
  console.log(`   Temperature: ${temperature}`);
  console.log(`   Max Tokens: ${maxTokens}`);
  console.log(`   Prompt: "${prompt}"\n`);

  console.log('⏳ Generating response...\n');

  try {
    const startTime = Date.now();

    // Generate text using AI SDK
    const result = await generateText({
      model: openai(model, {
        // Optional: customize model settings
      }),
      prompt: prompt,
      temperature: temperature,
      maxTokens: maxTokens,
    });

    const duration = Date.now() - startTime;

    console.log('✨ Response:');
    console.log('--------------------------------------------------');
    console.log(result.text);
    console.log('--------------------------------------------------\n');

    console.log('📊 Metadata:');
    console.log(`   Completion Tokens: ${result.usage.completionTokens}`);
    console.log(`   Prompt Tokens: ${result.usage.promptTokens}`);
    console.log(`   Total Tokens: ${result.usage.totalTokens}`);
    console.log(`   Duration: ${duration}ms`);
    console.log(`   Finish Reason: ${result.finishReason}\n`);

    // Show reasoning tokens if available (for reasoning models like o1)
    if (result.providerMetadata?.openai?.reasoningTokens) {
      console.log(`   Reasoning Tokens: ${result.providerMetadata.openai.reasoningTokens}`);
    }

    // Show cached tokens if prompt caching was used
    if (result.providerMetadata?.openai?.cachedPromptTokens) {
      console.log(`   Cached Prompt Tokens: ${result.providerMetadata.openai.cachedPromptTokens}`);
    }

    console.log('✅ Generation completed successfully!\n');

  } catch (error) {
    console.error('❌ Error:', error.message);
    if (error.cause) {
      console.error('   Cause:', error.cause);
    }
    process.exit(1);
  }
}

main().catch(console.error);
