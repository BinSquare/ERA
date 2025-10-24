#!/usr/bin/env node
/**
 * Async/Await Example in JavaScript
 * Demonstrates promises, async/await, and timing
 */

// Helper function to simulate async work
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Async function to fetch some "data"
async function fetchData(id) {
  console.log(`Fetching data for ID: ${id}...`);
  await delay(100); // Simulate network delay
  return {
    id,
    timestamp: new Date().toISOString(),
    data: `Result for ${id}`
  };
}

// Main async function
async function main() {
  console.log("Starting async operations...\n");

  // Sequential operations
  console.log("Sequential fetches:");
  const result1 = await fetchData(1);
  console.log(`Got: ${JSON.stringify(result1)}`);

  const result2 = await fetchData(2);
  console.log(`Got: ${JSON.stringify(result2)}\n`);

  // Parallel operations
  console.log("Parallel fetches:");
  const [result3, result4, result5] = await Promise.all([
    fetchData(3),
    fetchData(4),
    fetchData(5)
  ]);

  console.log("Got all results:");
  console.log(JSON.stringify([result3, result4, result5], null, 2));

  console.log("\n✓ All async operations completed!");
}

// Run the main function
main().catch(err => {
  console.error("Error:", err.message);
  process.exit(1);
});
