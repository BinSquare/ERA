#!/usr/bin/env python3
"""
Data Processing Example in Python
Demonstrates working with lists, dictionaries, and JSON
"""

import json

# Process a list of numbers
numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
print(f"Original numbers: {numbers}")

# Calculate squares
squared = [n**2 for n in numbers]
print(f"Squared: {squared}")

# Calculate sum
total = sum(squared)
print(f"Sum of squares: {total}")

# Filter even numbers
evens = [n for n in numbers if n % 2 == 0]
print(f"Even numbers: {evens}")

# Create a result object
result = {
    "status": "success",
    "count": len(numbers),
    "sum_of_squares": total,
    "even_numbers": evens,
    "statistics": {
        "min": min(numbers),
        "max": max(numbers),
        "avg": sum(numbers) / len(numbers)
    }
}

# Output as JSON
print("\nResult as JSON:")
print(json.dumps(result, indent=2))
