#!/bin/bash
# Test script for /api/execute endpoint
# Usage: ./test-execute.sh [BASE_URL]
# Example: ./test-execute.sh https://era-agent.yawnxyz.workers.dev

set -e

BASE_URL="${1:-http://localhost:8787}"
PASSED=0
FAILED=0

echo "Testing ERA Agent /api/execute endpoint"
echo "Base URL: $BASE_URL"
echo "=============================================="
echo

# Helper function to run a test
run_test() {
    local test_name="$1"
    local language="$2"
    local code="$3"
    local expected_exit_code="${4:-0}"

    echo "Test: $test_name"

    # Create JSON payload
    local json_payload=$(jq -n \
        --arg code "$code" \
        --arg language "$language" \
        --argjson timeout 30 \
        '{code: $code, language: $language, timeout: $timeout}')

    # Make request
    local response=$(curl -sf -X POST "$BASE_URL/api/execute" \
        -H "Content-Type: application/json" \
        -d "$json_payload" 2>&1)

    if [ $? -ne 0 ]; then
        echo "  ❌ Request failed: $response"
        ((FAILED++))
        echo
        return 1
    fi

    # Parse response
    local exit_code=$(echo "$response" | jq -r '.exit_code')
    local stdout=$(echo "$response" | jq -r '.stdout')
    local stderr=$(echo "$response" | jq -r '.stderr')
    local duration=$(echo "$response" | jq -r '.duration')

    # Check exit code
    if [ "$exit_code" != "$expected_exit_code" ]; then
        echo "  ❌ Expected exit code $expected_exit_code, got $exit_code"
        echo "  stdout: $stdout"
        echo "  stderr: $stderr"
        ((FAILED++))
    else
        echo "  ✓ Exit code: $exit_code"
        echo "  Duration: $duration"
        if [ -n "$stdout" ] && [ "$stdout" != "null" ]; then
            echo "  Output:"
            echo "$stdout" | sed 's/^/    /'
        fi
        ((PASSED++))
    fi
    echo
}

# Python Tests
echo "=== Python Tests ==="
echo

run_test "Python: Simple arithmetic" "python" "print(2 + 2)"

run_test "Python: Loop" "python" "for i in range(5):
    print(i)"

run_test "Python: List comprehension" "python" "numbers = [1, 2, 3, 4, 5]
squared = [n**2 for n in numbers]
print(squared)"

run_test "Python: JSON output" "python" "import json
data = {'result': 42, 'status': 'success'}
print(json.dumps(data))"

run_test "Python: Data processing" "python" "numbers = [1, 2, 3, 4, 5]
total = sum(numbers)
average = total / len(numbers)
print(f'Sum: {total}, Average: {average}')"

# JavaScript Tests
echo "=== JavaScript Tests ==="
echo

run_test "JavaScript: Simple arithmetic" "javascript" "console.log(2 + 2);"

run_test "JavaScript: Array methods" "javascript" "const arr = [1, 2, 3, 4, 5];
const doubled = arr.map(n => n * 2);
console.log('Doubled:', doubled);"

run_test "JavaScript: JSON output" "js" "const data = { result: 42, status: 'success' };
console.log(JSON.stringify(data));"

run_test "JavaScript: Reduce" "node" "const numbers = [1, 2, 3, 4, 5];
const sum = numbers.reduce((a, b) => a + b, 0);
console.log('Sum:', sum);"

run_test "JavaScript: Object destructuring" "javascript" "const person = { name: 'Alice', age: 30 };
const { name, age } = person;
console.log(\`\${name} is \${age} years old\`);"

# TypeScript Tests
echo "=== TypeScript Tests ==="
echo

run_test "TypeScript: Simple types" "typescript" "const message: string = 'Hello TypeScript';
const count: number = 42;
console.log(\`\${message}: \${count}\`);"

run_test "TypeScript: Array types" "ts" "const numbers: number[] = [1, 2, 3, 4, 5];
const doubled: number[] = numbers.map((n: number) => n * 2);
console.log('Doubled:', doubled);"

run_test "TypeScript: Interface" "typescript" "interface Person {
  name: string;
  age: number;
}
const alice: Person = { name: 'Alice', age: 30 };
console.log(\`\${alice.name} is \${alice.age}\`);"

# Error Tests
echo "=== Error Handling Tests ==="
echo

run_test "Python: Syntax error" "python" "print('unclosed string" 1

run_test "JavaScript: Runtime error" "javascript" "throw new Error('Test error');" 1

# Summary
echo "=============================================="
echo "Test Summary:"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "=============================================="

if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
