#!/usr/bin/env node
/**
 * Modern JavaScript (ES6+) Features
 * Demonstrates arrow functions, destructuring, template literals, etc.
 */

// Arrow functions
const greet = (name) => `Hello, ${name}!`;
console.log(greet("ERA Agent"));

// Destructuring
const person = { name: "Alice", age: 30, city: "NYC" };
const { name, age, city } = person;
console.log(`${name} is ${age} years old and lives in ${city}`);

// Array destructuring
const [first, second, ...rest] = [1, 2, 3, 4, 5];
console.log(`First: ${first}, Second: ${second}, Rest: ${rest}`);

// Spread operator
const arr1 = [1, 2, 3];
const arr2 = [4, 5, 6];
const combined = [...arr1, ...arr2];
console.log(`Combined: ${combined}`);

// Template literals
const x = 10;
const y = 20;
console.log(`Sum: ${x + y}, Product: ${x * y}`);

// Object shorthand
const makeUser = (name, age) => ({ name, age });
const user = makeUser("Bob", 25);
console.log(`User: ${JSON.stringify(user)}`);

// Default parameters
const multiply = (a, b = 2) => a * b;
console.log(`5 * 2 = ${multiply(5)}`);
console.log(`5 * 3 = ${multiply(5, 3)}`);

// Array methods (map, filter, reduce)
const numbers = [1, 2, 3, 4, 5];
const doubled = numbers.map(n => n * 2);
const evens = numbers.filter(n => n % 2 === 0);
const sum = numbers.reduce((acc, n) => acc + n, 0);

console.log(`\nArray operations:`);
console.log(`Doubled: ${doubled}`);
console.log(`Evens: ${evens}`);
console.log(`Sum: ${sum}`);

// Optional chaining
const data = { user: { profile: { email: "test@example.com" } } };
console.log(`\nEmail: ${data?.user?.profile?.email}`);
console.log(`Phone (missing): ${data?.user?.phone ?? "N/A"}`);
