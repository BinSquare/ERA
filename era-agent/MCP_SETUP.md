# ERA Agent MCP Server Setup Guide

This guide explains how to set up and use the ERA Agent MCP (Model Context Protocol) server with Claude Desktop.

## What is MCP?

The Model Context Protocol (MCP) is a standardized protocol that allows AI assistants like Claude to interact with external tools and services. The ERA Agent MCP server exposes ERA Agent's code execution capabilities as MCP tools that Claude can use directly.

## Prerequisites

- Go 1.21 or later
- Firecracker (for Linux) or Docker (for macOS)
- Claude Desktop application

## Building the ERA Agent MCP Server

1. Clone the repository and navigate to the era-agent directory:

```bash
cd era-agent
```

2. Build the agent binary:

```bash
go build -o agent
```

3. Verify the build:

```bash
./agent help
```

## Starting the MCP Server

To start the MCP server in standalone mode:

```bash
./agent mcp
```

The server will:
- Start listening on stdin/stdout for MCP protocol messages
- Initialize the VM service for code execution
- Wait for requests from Claude Desktop

**Note:** The MCP server runs in the foreground. Use Ctrl+C to stop it.

## Claude Desktop Configuration

To connect Claude Desktop to your ERA Agent MCP server, you need to configure it in Claude Desktop's settings.

### macOS Configuration

1. Open Claude Desktop
2. Go to **Settings** → **Developer** → **MCP Servers**
3. Click **Add Server** or edit the configuration file directly

The configuration file is located at:
```
~/Library/Application Support/Claude/claude_desktop_config.json
```

4. Add the ERA Agent MCP server configuration:

```json
{
  "mcpServers": {
    "era-agent": {
      "command": "/absolute/path/to/era-agent/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_LOG_LEVEL": "info"
      }
    }
  }
}
```

**Important:** Replace `/absolute/path/to/era-agent/agent` with the actual absolute path to your built agent binary.

### Linux Configuration

The configuration file is located at:
```
~/.config/Claude/claude_desktop_config.json
```

Use the same JSON configuration as shown for macOS.

### Windows Configuration

The configuration file is located at:
```
%APPDATA%\Claude\claude_desktop_config.json
```

Use the same JSON configuration as shown for macOS (with Windows-style paths).

## Available MCP Tools

Once configured, Claude will have access to the following ERA Agent tools:

### 1. era_execute_code
Execute code in an ephemeral sandbox environment.

**Parameters:**
- `code` (required): The code to execute
- `language` (required): Programming language (`python`, `node`, `typescript`, `go`, `deno`)
- `files` (optional): Object mapping filenames to content
- `envs` (optional): Object with environment variables
- `timeout` (optional): Execution timeout in seconds (default: 30)

**Example usage in Claude:**
```
Can you execute this Python code:
print("Hello from ERA Agent!")
```

### 2. era_create_session
Create a persistent execution session that maintains state across multiple runs.

**Parameters:**
- `language` (required): Programming language
- `cpu_count` (optional): CPU count (default: 1)
- `memory_mib` (optional): Memory in MiB (default: 256)
- `network_mode` (optional): Network mode (`none`, `allow_all`)
- `persist` (optional): Enable persistence (default: false)
- `default_timeout` (optional): Default timeout for runs in this session

**Example usage in Claude:**
```
Create a Python session with 2 CPUs and 512MB memory
```

### 3. era_run_in_session
Execute code in an existing session, maintaining state between runs.

**Parameters:**
- `session_id` (required): Session ID from `era_create_session`
- `code` (required): Code to execute
- `timeout` (optional): Timeout override for this run
- `envs` (optional): Environment variables for this run

**Example usage in Claude:**
```
In session abc123, run: x = 42
Then run: print(x)
```

### 4. era_list_sessions
List all active sessions.

**Example usage in Claude:**
```
Show me all active ERA Agent sessions
```

### 5. era_get_session
Get details about a specific session.

**Parameters:**
- `session_id` (required): Session ID to query

**Example usage in Claude:**
```
What's the status of session abc123?
```

### 6. era_delete_session
Delete a session and clean up its resources.

**Parameters:**
- `session_id` (required): Session ID to delete
- `keep_persist` (optional): Keep persistent storage (default: false)

**Example usage in Claude:**
```
Delete session abc123
```

### 7. era_upload_file
Upload a file to a session's workspace.

**Parameters:**
- `session_id` (required): Target session ID
- `path` (required): File path in session workspace
- `content` (required): File content

**Example usage in Claude:**
```
Upload a requirements.txt file to session abc123 with content:
requests==2.31.0
numpy==1.24.0
```

### 8. era_read_file
Read a file from a session's workspace.

**Parameters:**
- `session_id` (required): Source session ID
- `path` (required): File path to read

**Example usage in Claude:**
```
Read the output.txt file from session abc123
```

### 9. era_list_files
List all files in a session's workspace.

**Parameters:**
- `session_id` (required): Session ID to query

**Example usage in Claude:**
```
What files exist in session abc123?
```

## Available MCP Resources

The ERA Agent MCP server also exposes resources that Claude can read:

### Session Resources
- URI: `session://{session_id}`
- Returns: JSON with session metadata (ID, language, status, timestamps, etc.)

### Files Resources
- URI: `session://{session_id}/files`
- Returns: JSON array of files in the session workspace with paths and sizes

## Example Workflows

### Quick Code Execution
```
User: Run this Python code: print(sum([1, 2, 3, 4, 5]))

Claude uses: era_execute_code
Result: 15
```

### Stateful Multi-Step Execution
```
User: Create a Python session and run a multi-step calculation

Claude:
1. Uses era_create_session to create a Python session
2. Uses era_run_in_session to run: data = [1, 2, 3, 4, 5]
3. Uses era_run_in_session to run: average = sum(data) / len(data)
4. Uses era_run_in_session to run: print(f"Average: {average}")

Result: Average: 3.0
```

### File-Based Workflow
```
User: Create a Python script that processes data

Claude:
1. Uses era_create_session to create a session
2. Uses era_upload_file to upload data.csv
3. Uses era_upload_file to upload process.py script
4. Uses era_run_in_session to run: python process.py
5. Uses era_read_file to retrieve the output
```

## Logging

Control log verbosity with the `AGENT_LOG_LEVEL` environment variable:

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

Available log levels: `debug`, `info`, `warn`, `error`

## Troubleshooting

### Claude Desktop doesn't show ERA Agent tools

1. Verify the configuration file path is correct for your OS
2. Check that the `command` path points to the correct agent binary location (use absolute paths)
3. Restart Claude Desktop after configuration changes
4. Check Claude Desktop's MCP logs (usually in the Developer section)

### MCP server fails to start

1. Ensure Firecracker (Linux) or Docker (macOS) is properly installed
2. Check that the agent binary has execute permissions: `chmod +x agent`
3. Try running `./agent mcp` manually to see error messages
4. Check the `AGENT_LOG_LEVEL` is set to `debug` for more detailed logs

### Code execution times out

1. Increase the timeout parameter in your code execution requests
2. For sessions, set a higher `default_timeout` when creating the session
3. Check if the code is stuck in an infinite loop
4. Verify network access if the code needs internet connectivity (use `network_mode: "allow_all"`)

### Session not persisting data

1. Ensure `persist: true` was set when creating the session
2. Check that you're using the correct `session_id` for subsequent runs
3. Verify the session hasn't been deleted or cleaned up

## Advanced Configuration

### Custom State Directory

Override the state directory location:

```json
{
  "mcpServers": {
    "era-agent": {
      "command": "/path/to/agent",
      "args": ["mcp"],
      "env": {
        "AGENT_STATE_DIR": "/custom/path/to/state",
        "AGENT_LOG_LEVEL": "info"
      }
    }
  }
}
```

### Multiple ERA Agent Instances

You can configure multiple ERA Agent MCP servers with different settings:

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
        "AGENT_LOG_LEVEL": "debug"
      }
    }
  }
}
```

## Security Considerations

- The ERA Agent MCP server executes code in isolated sandboxes (Firecracker VMs)
- By default, network access is disabled for security
- Persistent sessions store data locally in the state directory
- Always review code before execution, especially from untrusted sources
- The MCP protocol uses stdio transport, providing local-only access

## Performance Tips

1. **Reuse sessions** for related operations to avoid VM startup overhead
2. **Set appropriate timeouts** to balance between responsiveness and allowing long-running operations
3. **Use persistent sessions** when you need to maintain state across multiple interactions
4. **Clean up sessions** when done to free resources: use `era_delete_session`

## Support and Resources

- ERA Agent Repository: [GitHub Link]
- MCP Protocol Specification: https://modelcontextprotocol.io
- Report Issues: [GitHub Issues Link]

## Next Steps

After setting up the MCP server:

1. Try executing simple code snippets with Claude
2. Create a persistent session and explore stateful execution
3. Upload files and process them in a session
4. Experiment with different programming languages (Python, Node.js, TypeScript, Go, Deno)

For more information about ERA Agent's capabilities, see the main README.md.
