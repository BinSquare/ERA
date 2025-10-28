# ERA Agent - Code Examples

This directory contains example scripts demonstrating various features of ERA Agent with both Python and JavaScript/TypeScript.

## 📚 Examples

### Basic Examples

#### `hello.py` & `hello.js`
Simple "Hello World" examples showing basic output.

**Python:**
```bash
curl -X POST http://localhost:8787/api/vm/python-xxx/run \
  -H "Content-Type: application/json" \
  -d '{"command":"python3 examples/hello.py","timeout":30}'
```

**JavaScript:**
```bash
curl -X POST http://localhost:8787/api/vm/node-xxx/run \
  -H "Content-Type: application/json" \
  -d '{"command":"node examples/hello.js","timeout":30}'
```

### Data Processing

#### `data-processing.py` & `data-processing.js`
Demonstrates working with collections, data manipulation, and JSON output.

**Features:**
- Array/List operations (map, filter, reduce)
- Mathematical calculations
- JSON serialization
- Statistics computation

**Python:**
```bash
curl -X POST http://localhost:8787/api/vm/python-xxx/run \
  -H "Content-Type: application/json" \
  -d '{"command":"python3 examples/data-processing.py","timeout":30}'
```

**JavaScript:**
```bash
curl -X POST http://localhost:8787/api/vm/node-xxx/run \
  -H "Content-Type: application/json" \
  -d '{"command":"node examples/data-processing.js","timeout":30}'
```

### Object-Oriented Programming

#### `classes.py` & `classes.js`
Examples of classes, inheritance, and OOP patterns.

**Features:**
- Class definitions
- Inheritance
- Methods and properties
- Data classes / Plain objects

### JavaScript-Specific Examples

#### `modern-js.js`
Showcases modern JavaScript (ES6+) features:
- Arrow functions
- Destructuring
- Spread operator
- Template literals
- Default parameters
- Optional chaining
- Array methods

```bash
curl -X POST http://localhost:8787/api/vm/node-xxx/run \
  -H "Content-Type: application/json" \
  -d '{"command":"node examples/modern-js.js","timeout":30}'
```

#### `async-example.js`
Demonstrates asynchronous JavaScript:
- Promises
- async/await
- Sequential vs parallel operations
- Error handling

```bash
curl -X POST http://localhost:8787/api/vm/node-xxx/run \
  -H "Content-Type: application/json" \
  -d '{"command":"node examples/async-example.js","timeout":30}'
```

## 🚀 Quick Test

Use the included test scripts to run all examples:

```bash
# Test all examples on production
./test-simple.sh https://era-agent.YOUR_SUBDOMAIN.workers.dev

# Test locally
./test-simple.sh http://localhost:8787
```

## 💡 Inline Examples

You can also run code directly without files:

### Python Inline
```bash
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/vm/python-xxx/run \
  -H "Content-Type: application/json" \
  -d '{"command":"python3 -c \"print(2+2)\"","timeout":30}'
```

### JavaScript Inline
```bash
curl -X POST https://era-agent.YOUR_SUBDOMAIN.workers.dev/api/vm/node-xxx/run \
  -H "Content-Type: application/json" \
  -d '{"command":"node -e \"console.log(2+2)\"","timeout":30}'
```

## 🎓 Writing Your Own Examples

### Python Guidelines
- Use Python 3.11+ features
- Import modules as needed (json, sys, etc.)
- Print results to stdout
- Use `if __name__ == "__main__":` for scripts

### JavaScript Guidelines
- Use Node.js 20+ features
- Modern ES6+ syntax is fully supported
- Use console.log for output
- async/await is supported
- No TypeScript compilation needed (use .js files)

## 🔧 Testing Your Examples Locally

1. Start the agent:
```bash
cd era-agent
./agent serve
```

2. Create a VM:
```bash
curl -X POST http://localhost:8787/api/vm \
  -H "Content-Type: application/json" \
  -d '{"language":"python","cpu_count":1,"memory_mib":256}' \
  | jq -r '.id'
```

3. Run your example:
```bash
curl -X POST http://localhost:8787/api/vm/YOUR_VM_ID/run \
  -H "Content-Type: application/json" \
  -d '{"command":"python3 examples/your-script.py","timeout":30}' \
  | jq -r '.stdout'
```

## 📦 Available Runtimes

- **Python 3.11.14** - Full standard library
- **Node.js 20.15.1** - Modern JavaScript/ES6+
- **npm** - Available for installing packages (if needed)

## 🌐 TypeScript Support

While there's no built-in TypeScript compiler, you can:
1. Use JavaScript with JSDoc for type hints
2. Pre-compile TypeScript locally and run the .js output
3. Use modern JavaScript which has most TypeScript-like features

## 📝 Example Output Format

All examples return JSON with:
```json
{
  "exit_code": 0,
  "stdout": "output here...",
  "stderr": "",
  "duration": "123.456ms"
}
```

## 🤝 Contributing Examples

To add new examples:
1. Create both Python (.py) and JavaScript (.js) versions
2. Add clear comments explaining what the code does
3. Test locally before committing
4. Update this README with usage instructions
