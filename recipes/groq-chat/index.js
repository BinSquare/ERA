// Groq Chat API Example
// Fast inference with open-source models

import OpenAI from "openai";

const client = new OpenAI({
    apiKey: process.env.GROQ_API_KEY,
    baseURL: "https://api.groq.com/openai/v1",
});

async function main() {
    console.log("🚀 Calling Groq API...");

    const chatCompletion = await client.chat.completions.create({
        messages: [
            {
                role: "user",
                content: process.env.PROMPT || "Explain the importance of fast language models in 2-3 sentences",
            }
        ],
        model: process.env.MODEL || "llama-3.3-70b-versatile",
        temperature: parseFloat(process.env.TEMPERATURE || "0.7"),
        max_tokens: parseInt(process.env.MAX_TOKENS || "150"),
    });

    console.log("\n✨ Response:");
    console.log(chatCompletion.choices[0].message.content);
    console.log(`\n📊 Model: ${chatCompletion.model}`);
    console.log(`⚡ Tokens: ${chatCompletion.usage.total_tokens}`);
}

main().catch(console.error);
