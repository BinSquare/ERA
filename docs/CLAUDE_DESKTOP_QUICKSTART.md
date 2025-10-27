# Claude Desktop + ERA Agent MCP: Quick Start Guide

Get Claude Desktop running code with ERA Agent in 5 minutes.

## Prerequisites

- Claude Desktop installed
- Go 1.21+ installed
- Docker running (macOS) OR Firecracker setup (Linux)

## Step 1: Build ERA Agent

```bash
cd era-agent
go build -o agent
```

Verify it built successfully:
```bash
ls -lh agent
# Should show: -rwxr-xr-x ... agent
```

**Important:** If you get an EACCESS error later, make sure the binary is executable:
```bash
chmod +x agent
```

## Step 2: Get the Full Path to Your Agent Binary

This is CRITICAL - you need the absolute path:

```bash
pwd
# Output example: /Users/yourusername/era-agent
```

Your full path will be: `/Users/yourusername/era-agent/agent`

**Write this down!** You'll need it in the next step.

## Step 3: Configure Claude Desktop

### Find Your Config File

**macOS:**
```bash
cursor "~/Library/Application\ Support/Claude/claude_desktop_config.json"
```

**Linux:**
```bash
code ~/.config/Claude/claude_desktop_config.json
```

**Windows:**
```bash
notepad %APPDATA%\Claude\claude_desktop_config.json
```

### Add ERA Agent Configuration

Replace the entire contents with this (update the path!):

```json
{
  "mcpServers": {
    "era-agent": {
      "command": "/REPLACE/WITH/YOUR/FULL/PATH/TO/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_LOG_LEVEL": "info"
      }
    }
  }
}
```

**IMPORTANT:** Replace `/REPLACE/WITH/YOUR/FULL/PATH/TO/agent` with your actual path from Step 2.

**Example (macOS):**
```json
{
  "mcpServers": {
    "era-agent": {
      "command": "/Users/janzheng/era-agent/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_LOG_LEVEL": "info"
      }
    }
  }
}
```

**Example (Linux):**
```json
{
  "mcpServers": {
    "era-agent": {
      "command": "/home/janzheng/era-agent/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_LOG_LEVEL": "info"
      }
    }
  }
}
```

Save the file.

## Step 4: Restart Claude Desktop

**Completely quit** Claude Desktop (don't just close the window):

**macOS:** Cmd+Q or Claude Desktop → Quit
**Linux:** File → Quit
**Windows:** File → Exit

Then restart Claude Desktop.

## Step 5: Verify Connection

In Claude Desktop, look for:
- A small tool icon or "MCP" indicator in the interface
- Check Settings → Developer → MCP Servers to see if "era-agent" appears

If you don't see it, check the logs:

**macOS:**
```bash
tail -f ~/Library/Logs/Claude/mcp*.log
```

**Linux:**
```bash
tail -f ~/.config/Claude/logs/mcp*.log
```

## Step 6: Test It!

Open Claude Desktop and try these prompts:

### Test 1: Simple Execution
```
Execute this Python code:
print("Hello from ERA Agent!")
print(f"2 + 2 = {2 + 2}")
```

**Expected Result:** Claude should use `era_execute_code` and show you the output.

### Test 2: Create a Session
```
Create a Python session and run this code:
counter = 0
print(f"Counter initialized: {counter}")
```

**Expected Result:** Claude should use `era_create_session` and give you a session ID.

### Test 3: Stateful Execution
```
In the same session, run:
counter += 1
print(f"Counter is now: {counter}")
```

**Expected Result:** Should output "Counter is now: 1" (maintaining state from previous run).

### Test 4: Multi-Language
```
Execute this Node.js code:
console.log("Hello from Node!");
const data = [1, 2, 3, 4, 5];
console.log("Sum:", data.reduce((a, b) => a + b, 0));
```

**Expected Result:** Claude should execute Node.js code and show the sum.

## Troubleshooting

### "Command not found" or "Failed to start MCP server"

**Problem:** The path to your agent binary is wrong.

**Fix:**
1. Verify the binary exists:
   ```bash
   ls -l /your/path/to/agent
   ```
2. Use an absolute path (starting with `/`), NOT a relative path
3. Make sure the binary has execute permissions:
   ```bash
   chmod +x /your/path/to/agent
   ```

### Claude doesn't show ERA Agent tools

**Problem:** Configuration not loaded or MCP server failed to start.

**Fix:**
1. Check the config file syntax (valid JSON?)
2. Restart Claude Desktop completely (Cmd+Q on macOS)
3. Check Claude Desktop logs for errors
4. Try debug logging:
   ```json
   "env": {
     "AGENT_LOG_LEVEL": "debug"
   }
   ```

### Code execution fails with "VM service error"

**Problem:** Docker (macOS) or Firecracker (Linux) not running.

**Fix (macOS):**
1. Open Docker Desktop
2. Verify it's running: `docker ps` should work
3. Restart Claude Desktop

**Fix (Linux):**
1. Verify Firecracker is installed
2. Check permissions for `/dev/kvm`
3. See ERA Agent documentation for Firecracker setup

### "Context deadline exceeded" or timeout errors

**Problem:** Code is taking too long or VM startup is slow.

**Fix:**
1. Increase timeout in your requests
2. For sessions, set a default_timeout:
   ```
   Create a Python session with a 60 second default timeout
   ```

### ERA Agent works in terminal but not in Claude Desktop

**Problem:** Environment variables or PATH not set correctly.

**Fix:** Add environment variables to the config:
```json
{
  "mcpServers": {
    "era-agent": {
      "command": "/full/path/to/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_LOG_LEVEL": "info",
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/Users/yourusername"
      }
    }
  }
}
```

### "timeout" error or MCP server won't start

**Problem:** Another ERA Agent process is already running and has locked the database.

**Fix:**
1. Check for running agent processes:
   ```bash
   ps aux | grep '[a]gent' | grep -E 'mcp|serve'
   ```

2. Kill any running agent processes:
   ```bash
   # Replace PID with the actual process ID from the ps command
   kill <PID>
   ```

3. Restart Claude Desktop completely (Cmd+Q on macOS)

## Advanced Usage

### Debug Mode

For detailed logs, enable debug mode:

```json
{
  "mcpServers": {
    "era-agent": {
      "command": "/path/to/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_LOG_LEVEL": "debug"
      }
    }
  }
}
```

Then check the logs to see detailed request/response information.

### Custom State Directory

Store sessions in a custom location:

```json
{
  "mcpServers": {
    "era-agent": {
      "command": "/path/to/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_STATE_DIR": "/path/to/custom/state",
        "AGENT_LOG_LEVEL": "info"
      }
    }
  }
}
```

### Multiple Configurations

Run different ERA Agent instances:

```json
{
  "mcpServers": {
    "era-agent-default": {
      "command": "/path/to/agent",
      "args": ["mcp"]
    },
    "era-agent-debug": {
      "command": "/path/to/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_LOG_LEVEL": "debug",
        "AGENT_STATE_DIR": "/tmp/era-debug"
      }
    }
  }
}
```

## What Claude Can Do With ERA Agent

Once connected, Claude can:

### 1. Execute Code in Multiple Languages
- Python
- Node.js
- TypeScript
- Go
- Deno

### 2. Create Persistent Sessions
- Maintain state across multiple executions
- Upload files to session workspace
- Read files from session
- Multi-step workflows

### 3. Work with Files
- Upload data files
- Process files with code
- Read output files
- List all files in session

### 4. Network Access (Optional)
Ask Claude to:
```
Create a Python session with network access enabled, then fetch data from an API
```

### 5. Complex Workflows
Example prompts:
```
Create a Python session, upload this CSV data, analyze it, and create a summary report
```

```
Write a Node.js script that processes JSON data, run it, and show me the results
```

```
Create a Go session, write a simple HTTP server, and show me how to run it
```

## Example Session Transcript

**You:** "Execute this Python code: `import sys; print(f'Python version: {sys.version}')`"

**Claude:** I'll execute that Python code for you.

*[Uses era_execute_code tool]*

**Claude:** The code executed successfully:
```
Python version: 3.11.0 (main, Oct 24 2023, 12:00:00)
```

**You:** "Now create a persistent Python session"

**Claude:** I'll create a persistent Python session.

*[Uses era_create_session tool]*

**Claude:** Session created with ID: `abc-123-xyz`. This session will maintain state between executions.

**You:** "In that session, set x = 42, then in the next run print x"

**Claude:** I'll run these operations in sequence.

*[Uses era_run_in_session twice]*

**Claude:**
First run: Variable x set to 42
Second run: Output: `42`

The session successfully maintained state between executions!

## Next Steps

- Read [MCP_SETUP.md](./MCP_SETUP.md) for complete tool documentation
- See [mcp/README.md](./mcp/README.md) for implementation details
- Try different languages: Python, Node.js, TypeScript, Go, Deno
- Experiment with persistent sessions for complex workflows
- Upload files and process them with code

## Getting Help

- Check logs: `~/Library/Logs/Claude/mcp*.log` (macOS)
- Enable debug logging in config
- Verify Docker/Firecracker is running
- Make sure the agent binary path is absolute
- Test the MCP server manually: `./agent mcp`

## Common Claude Prompts

Here are some useful prompts to try:

```
"Execute this Python code: [your code]"
"Create a Node.js session"
"In session [id], run: [your code]"
"List all active sessions"
"Upload a file called data.txt to session [id] with content: [content]"
"Read the file output.txt from session [id]"
"Delete session [id]"
"Create a Python session with 2 CPUs and 512MB memory"
"Execute this code with network access enabled: [code that needs internet]"
```

## Success Indicators

You'll know it's working when:

✅ Claude mentions using "era_execute_code" or other ERA tools
✅ You see code execution output in Claude's responses
✅ Sessions maintain state between runs
✅ Claude can list and manage multiple sessions
✅ File uploads and reads work correctly

## Security Note

- ERA Agent runs code in isolated Firecracker VMs
- Network access is disabled by default
- Sessions are local to your machine
- Always review code before executing

---

**You're ready to go!** Claude Desktop can now execute code using ERA Agent.
