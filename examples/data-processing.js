#!/usr/bin/env node
/**
 * Data Processing Example in JavaScript
 * Demonstrates working with arrays, objects, and JSON
 */

// Process an array of numbers
const numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
console.log(`Original numbers: ${JSON.stringify(numbers)}`);

// Calculate squares
const squared = numbers.map(n => n ** 2);
console.log(`Squared: ${JSON.stringify(squared)}`);

// Calculate sum
const total = squared.reduce((acc, n) => acc + n, 0);
console.log(`Sum of squares: ${total}`);

// Filter even numbers
const evens = numbers.filter(n => n % 2 === 0);
console.log(`Even numbers: ${JSON.stringify(evens)}`);

// Create a result object
const result = {
  status: "success",
  count: numbers.length,
  sum_of_squares: total,
  even_numbers: evens,
  statistics: {
    min: Math.min(...numbers),
    max: Math.max(...numbers),
    avg: numbers.reduce((a, b) => a + b, 0) / numbers.length
  }
};

// Output as JSON
console.log("\nResult as JSON:");
console.log(JSON.stringify(result, null, 2));
