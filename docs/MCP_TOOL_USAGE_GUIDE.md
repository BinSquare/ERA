# ERA Agent MCP Tools - Usage Guide

## Overview

The ERA Agent provides language-specific MCP tools for Claude Desktop. Each tool is designed to be clear and unambiguous about what language it executes.

## Available Tools

### 1. `era_python` - Python Code Execution
Execute Python code in an isolated environment.

**Parameters:**
- `code` (required): Python code to execute
- `timeout` (optional): Execution timeout in seconds (default: 30)

**Examples:**
```python
# Simple calculation
print(2 + 2)

# FizzBuzz
for i in range(1, 101):
    if i % 15 == 0:
        print("FizzBuzz")
    elif i % 3 == 0:
        print("Fizz")
    elif i % 5 == 0:
        print("Buzz")
    else:
        print(i)

# Data processing
import json
data = {"name": "Alice", "age": 30}
print(json.dumps(data, indent=2))
```

**Installing Packages:**
For ephemeral execution, packages are not persistent. Use sessions instead (see below).

---

### 2. `era_node` - Node.js/JavaScript Execution
Execute JavaScript code using Node.js.

**Parameters:**
- `code` (required): JavaScript code to execute
- `timeout` (optional): Execution timeout in seconds (default: 30)

**Examples:**
```javascript
// Simple output
console.log('Hello, World!')

// Array operations
const numbers = [1, 2, 3, 4, 5]
const doubled = numbers.map(n => n * 2)
console.log(doubled)

// Async/await
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms))
async function main() {
  console.log('Start')
  await sleep(1000)
  console.log('End')
}
main()
```

---

### 3. `era_typescript` - TypeScript Execution
Execute TypeScript code with type checking.

**Parameters:**
- `code` (required): TypeScript code to execute
- `timeout` (optional): Execution timeout in seconds (default: 30)

**Examples:**
```typescript
// Type-safe code
interface User {
  name: string
  age: number
}

const user: User = {
  name: 'Bob',
  age: 25
}

console.log(`${user.name} is ${user.age} years old`)
```

---

### 4. `era_deno` - Deno Execution
Execute code using Deno runtime.

**Parameters:**
- `code` (required): Deno code to execute
- `timeout` (optional): Execution timeout in seconds (default: 30)

**Examples:**
```typescript
// Deno-specific APIs
console.log(Deno.version)
console.log('Platform:', Deno.build.os)
```

---

### 5. `era_shell` - Shell Command Execution
Execute shell commands directly. **This is the key tool for package installation!**

**Parameters:**
- `command` (required): Shell command to execute
- `session_id` (optional): Run in a specific session for persistence
- `timeout` (optional): Execution timeout in seconds (default: 30)

**Examples:**
```bash
# List files
ls -la

# Install Python packages
pip install requests pandas numpy

# Install Node packages
npm install lodash axios

# Check Python version
python3 --version

# Create directory
mkdir -p /tmp/mydata

# Download file
curl -O https://example.com/data.json
```

---

## Package Installation Workflows

### Python with Packages (Using Sessions)

**Step 1: Create a session**
```
Use era_create_session with:
- session_id: "my-python-session"
- language: "python"
```

**Step 2: Install packages**
```
Use era_shell with:
- session_id: "my-python-session"
- command: "pip install requests beautifulsoup4"
```

**Step 3: Run code with packages**
```
Use era_run_in_session with:
- session_id: "my-python-session"
- code: "import requests; r = requests.get('https://api.github.com'); print(r.status_code)"
```

### Node.js with Packages (Using Sessions)

**Step 1: Create a session**
```
Use era_create_session with:
- session_id: "my-node-session"
- language: "node"
```

**Step 2: Install packages**
```
Use era_shell with:
- session_id: "my-node-session"
- command: "npm install lodash"
```

**Step 3: Run code with packages**
```
Use era_run_in_session with:
- session_id: "my-node-session"
- code: "const _ = require('lodash'); console.log(_.chunk([1,2,3,4], 2))"
```

---

## Session Management

### Creating a Session
```
Tool: era_create_session
Parameters:
  - session_id: "unique-id"
  - language: "python" | "node" | "typescript" | "deno" | "go"
  - default_timeout: 60 (optional)
```

### Running Code in a Session
```
Tool: era_run_in_session
Parameters:
  - session_id: "unique-id"
  - code: "your code here"
  - timeout: 30 (optional)
```

### Listing Sessions
```
Tool: era_list_sessions
```

### Deleting a Session
```
Tool: era_delete_session
Parameters:
  - session_id: "unique-id"
```

---

## File Management in Sessions

### Upload a File
```
Tool: era_upload_file
Parameters:
  - session_id: "unique-id"
  - file_path: "data.csv"
  - content: "col1,col2\n1,2\n3,4"
```

### Read a File
```
Tool: era_read_file
Parameters:
  - session_id: "unique-id"
  - file_path: "data.csv"
```

### List Files
```
Tool: era_list_files
Parameters:
  - session_id: "unique-id"
```

---

## Common Patterns

### Pattern 1: Quick Calculation (No Packages)
```
Just use era_python or era_node directly:
- era_python: "print(sum(range(1, 101)))"
```

### Pattern 2: Data Analysis (With Packages)
```
1. era_create_session (id: "analysis", language: "python")
2. era_shell (session_id: "analysis", command: "pip install pandas matplotlib")
3. era_upload_file (session_id: "analysis", file_path: "data.csv", content: "...")
4. era_run_in_session (session_id: "analysis", code: "import pandas as pd; df = pd.read_csv('data.csv'); print(df.describe())")
```

### Pattern 3: Web Scraping
```
1. era_create_session (id: "scraper", language: "python")
2. era_shell (session_id: "scraper", command: "pip install requests beautifulsoup4")
3. era_run_in_session (session_id: "scraper", code: "import requests; from bs4 import BeautifulSoup; ...")
```

### Pattern 4: Testing Multiple Languages
```
# Test in Python
era_python: "print('Python:', 2 ** 10)"

# Test in Node
era_node: "console.log('Node:', Math.pow(2, 10))"

# Test in TypeScript
era_typescript: "console.log('TypeScript:', Math.pow(2, 10))"
```

---

## Troubleshooting

### Issue: Package not found
**Solution:** Use `era_shell` to install the package first, within a session:
```
1. Create session
2. era_shell: "pip install <package>"
3. Run your code in the session
```

### Issue: Code with newlines fails
**Solution:** Just write clean code with proper indentation. The tools preserve newlines correctly.

### Issue: Session not found
**Solution:** Sessions may expire after inactivity. Create a new session and reinstall packages.

### Issue: Timeout errors
**Solution:** Increase the `timeout` parameter:
```
era_python: { code: "...", timeout: 60 }
```

---

## Best Practices

1. **Use language-specific tools** (`era_python`, `era_node`, etc.) instead of generic `era_execute_code`
2. **Use sessions for package-dependent code** to avoid reinstalling packages every time
3. **Use `era_shell` for package installation** - it's designed for this purpose
4. **Clean up sessions** with `era_delete_session` when done to free resources
5. **Set appropriate timeouts** for long-running operations
6. **Write clean, well-formatted code** - the tools preserve formatting

---

## Tool Summary Table

| Tool | Purpose | Use Case |
|------|---------|----------|
| `era_python` | Run Python code | Quick Python scripts |
| `era_node` | Run JavaScript | Quick JS/Node scripts |
| `era_typescript` | Run TypeScript | Type-safe code |
| `era_deno` | Run Deno code | Deno-specific features |
| `era_shell` | Run shell commands | **Package installation**, file operations |
| `era_create_session` | Create persistent env | Multi-step workflows |
| `era_run_in_session` | Run code in session | Code with dependencies |
| `era_list_sessions` | List active sessions | Session management |
| `era_delete_session` | Delete session | Cleanup |
| `era_upload_file` | Upload file to session | Data processing |
| `era_read_file` | Read file from session | View results |
| `era_list_files` | List session files | File management |

---

## Example: Complete Data Analysis Workflow

```
# Step 1: Create a Python session for data analysis
era_create_session:
  session_id: "data-analysis"
  language: "python"

# Step 2: Install required packages
era_shell:
  session_id: "data-analysis"
  command: "pip install pandas numpy matplotlib"

# Step 3: Upload dataset
era_upload_file:
  session_id: "data-analysis"
  file_path: "sales_data.csv"
  content: "date,product,sales\n2024-01-01,A,100\n2024-01-02,B,150\n..."

# Step 4: Analyze data
era_run_in_session:
  session_id: "data-analysis"
  code: |
    import pandas as pd
    import numpy as np

    df = pd.read_csv('sales_data.csv')
    print("Summary Statistics:")
    print(df.describe())

    print("\nTotal Sales by Product:")
    print(df.groupby('product')['sales'].sum())

# Step 5: Cleanup
era_delete_session:
  session_id: "data-analysis"
```

---

## Questions?

See the main README.md for more information about the ERA Agent architecture and deployment options.
