// OpenAI Chat API Example
// Using GPT models for conversational AI

import OpenAI from "openai";

const client = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
});

async function main() {
    console.log("🤖 Calling OpenAI API...");

    const completion = await client.chat.completions.create({
        messages: [
            {
                role: "system",
                content: process.env.SYSTEM_PROMPT || "You are a helpful assistant."
            },
            {
                role: "user",
                content: process.env.PROMPT || "Write a haiku about code execution in the cloud"
            }
        ],
        model: process.env.MODEL || "gpt-4o-mini",
        temperature: parseFloat(process.env.TEMPERATURE || "0.7"),
        max_tokens: parseInt(process.env.MAX_TOKENS || "200"),
    });

    console.log("\n✨ Response:");
    console.log(completion.choices[0].message.content);
    console.log(`\n📊 Model: ${completion.model}`);
    console.log(`⚡ Tokens: ${completion.usage.total_tokens}`);
    console.log(`💰 Estimated cost: $${(completion.usage.total_tokens * 0.0000015).toFixed(6)}`);
}

main().catch(console.error);
