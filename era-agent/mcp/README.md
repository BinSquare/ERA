# ERA Agent MCP Server Implementation

This directory contains the Model Context Protocol (MCP) server implementation for ERA Agent, written in Go.

## Architecture Overview

The MCP server follows a clean architecture with clear separation of concerns:

```
mcp/
├── server.go      # Core MCP server, JSON-RPC 2.0 protocol handler
├── tools.go       # MCP tools implementation (9 tools)
├── resources.go   # MCP resources implementation
└── README.md      # This file
```

## Core Components

### 1. Server (server.go)

The `Server` struct is the core of the MCP implementation:

```go
type Server struct {
    mu       sync.RWMutex
    handlers map[string]Handler
    logger   Logger
    vmSvc    VMService
}
```

**Key Features:**
- JSON-RPC 2.0 protocol implementation
- stdio-based transport (reads from stdin, writes to stdout)
- Thread-safe handler registration
- Context-based cancellation support
- Graceful error handling

**Main Methods:**
- `NewServer(logger Logger, vmSvc VMService) *Server` - Creates a new MCP server instance
- `Start(ctx context.Context) error` - Starts the server and processes requests
- `RegisterHandler(method string, handler Handler)` - Registers request handlers

**Request Flow:**
1. Read JSON-RPC request from stdin
2. Parse and validate request
3. Look up handler for the requested method
4. Execute handler with parsed parameters
5. Serialize response and write to stdout

### 2. Tools (tools.go)

Implements all 9 ERA Agent MCP tools as handler functions.

**Tool Categories:**

**Ephemeral Execution:**
- `era_execute_code` - Quick, stateless code execution

**Session Management:**
- `era_create_session` - Create persistent execution environment
- `era_list_sessions` - List all active sessions
- `era_get_session` - Get session details
- `era_delete_session` - Clean up session resources

**Session Operations:**
- `era_run_in_session` - Execute code in existing session
- `era_upload_file` - Upload file to session workspace
- `era_read_file` - Read file from session workspace
- `era_list_files` - List files in session workspace

**Handler Pattern:**
Each tool follows this pattern:
```go
func (s *Server) handleToolName(ctx context.Context, params json.RawMessage) (interface{}, error) {
    // 1. Parse parameters
    var args ToolArguments
    if err := json.Unmarshal(params, &args); err != nil {
        return nil, err
    }

    // 2. Validate input
    if args.RequiredField == "" {
        return nil, fmt.Errorf("missing required field")
    }

    // 3. Call VMService
    result, err := s.vmSvc.Operation(ctx, args)
    if err != nil {
        return nil, err
    }

    // 4. Return result
    return result, nil
}
```

### 3. Resources (resources.go)

Implements MCP resources for querying session state and files.

**Resource Types:**

**Session Resource:** `session://{id}`
- Returns JSON with session metadata
- Includes: ID, language, CPU, memory, network mode, status, timestamps

**Files Resource:** `session://{id}/files`
- Returns JSON array of files in session workspace
- Each file includes: path, size

**Resource Handler Flow:**
1. Parse resource URI
2. Extract session ID and resource type
3. Validate session exists
4. Read and format requested resource
5. Return as ResourceContent with appropriate MIME type

## Interfaces

The MCP package defines clean interfaces for dependency injection:

### Logger Interface
```go
type Logger interface {
    Info(msg string, fields map[string]interface{})
    Error(msg string, fields map[string]interface{})
}
```

Used for structured logging throughout the MCP server.

### VMService Interface
```go
type VMService interface {
    Create(ctx context.Context, opts interface{}) (interface{}, error)
    Run(ctx context.Context, opts interface{}) (interface{}, error)
    Get(vmID string) (interface{}, bool)
    List() []interface{}
    Clean(ctx context.Context, vmID string, keepPersist bool) error
    GetVMWorkDir(vmID string) string
}
```

Abstracts the VM management layer, allowing the MCP server to work with any implementation.

## Integration with ERA Agent

The MCP server integrates with ERA Agent through adapter patterns defined in `cli_mcp.go`:

### Logger Adapter
```go
type mcpLoggerAdapter struct {
    logger *Logger
}

func (a *mcpLoggerAdapter) Info(msg string, fields map[string]interface{}) {
    a.logger.Info(msg, fields)
}

func (a *mcpLoggerAdapter) Error(msg string, fields map[string]interface{}) {
    a.logger.Error(msg, fields)
}
```

### VMService Adapter
```go
type mcpVMServiceAdapter struct {
    vmService *VMService
}

func (a *mcpVMServiceAdapter) Create(ctx context.Context, opts interface{}) (interface{}, error) {
    optsMap := opts.(map[string]interface{})
    // Convert map to VMCreateOptions
    createOpts := VMCreateOptions{
        Language:    getString(optsMap, "language"),
        CPUCount:    getInt(optsMap, "cpu_count", 1),
        MemoryMiB:   getInt(optsMap, "memory_mib", 256),
        NetworkMode: getString(optsMap, "network_mode"),
        Persist:     getBool(optsMap, "persist", false),
    }
    record, err := a.vmService.Create(ctx, createOpts)
    return vmRecordToMap(record), nil
}
```

The adapters handle:
- Type conversions between `interface{}` and concrete types
- Mapping between MCP tool parameters and VMService options
- Converting VMService results to JSON-serializable maps

## Protocol Details

### JSON-RPC 2.0 Message Format

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "era_execute_code",
    "arguments": {
      "code": "print('Hello')",
      "language": "python"
    }
  }
}
```

**Success Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Exit Code: 0\n\nStdout:\nHello\n"
      }
    ]
  }
}
```

**Error Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32603,
    "message": "Internal error",
    "data": "detailed error message"
  }
}
```

### Standard MCP Methods

The server implements these standard MCP protocol methods:

- `initialize` - Protocol handshake and capability negotiation
- `tools/list` - Returns list of available tools
- `tools/call` - Executes a specific tool
- `resources/list` - Returns list of available resources
- `resources/read` - Reads a specific resource

## Error Handling

The MCP server uses standard JSON-RPC 2.0 error codes:

| Code | Message | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON received |
| -32601 | Method not found | Unknown method called |
| -32603 | Internal error | Server-side error during execution |

Tool-specific errors are returned with code -32603 and detailed error messages in the `data` field.

## Concurrency and Thread Safety

- The server processes each request in a separate goroutine
- Handler map is protected with `sync.RWMutex`
- VMService operations are expected to be thread-safe
- Context cancellation is propagated through all operations

## Testing Considerations

When testing the MCP server:

1. **Unit Testing:** Mock the `Logger` and `VMService` interfaces
2. **Integration Testing:** Use a test VMService implementation
3. **Protocol Testing:** Send JSON-RPC requests to stdin, verify stdout responses
4. **Error Testing:** Verify proper error handling and response format

Example mock setup:
```go
type mockLogger struct {}
func (m *mockLogger) Info(msg string, fields map[string]interface{}) {}
func (m *mockLogger) Error(msg string, fields map[string]interface{}) {}

type mockVMService struct {}
func (m *mockVMService) Create(ctx context.Context, opts interface{}) (interface{}, error) {
    return map[string]interface{}{"id": "test-123"}, nil
}
// ... implement other methods
```

## Extending the MCP Server

### Adding a New Tool

1. Define the tool in `tools.go` `handleToolsList()`:
```go
{
    Name:        "era_my_new_tool",
    Description: "Description of what it does",
    InputSchema: map[string]interface{}{
        "type": "object",
        "properties": map[string]interface{}{
            "my_param": map[string]interface{}{
                "type":        "string",
                "description": "Parameter description",
            },
        },
        "required": []string{"my_param"},
    },
}
```

2. Implement the handler:
```go
func (s *Server) handleMyNewTool(ctx context.Context, params json.RawMessage) (interface{}, error) {
    var args struct {
        MyParam string `json:"my_param"`
    }
    if err := json.Unmarshal(params, &args); err != nil {
        return nil, fmt.Errorf("invalid parameters: %w", err)
    }

    // Implementation here

    return result, nil
}
```

3. Register the handler in `NewServer()`:
```go
s.RegisterHandler("tools/call", s.handleToolsCall)
// Add handler for tool execution in handleToolsCall switch
```

### Adding a New Resource

1. Define resource in `handleResourcesList()`:
```go
resources = append(resources, Resource{
    URI:         "my-resource://identifier",
    Name:        "My Resource",
    Description: "Resource description",
    MIMEType:    "application/json",
})
```

2. Implement resource reader in `handleResourcesRead()`:
```go
if strings.HasPrefix(req.URI, "my-resource://") {
    return s.readMyResource(identifier)
}
```

3. Create resource reader function:
```go
func (s *Server) readMyResource(identifier string) (interface{}, error) {
    data := // fetch your data
    jsonData, err := json.MarshalIndent(data, "", "  ")
    if err != nil {
        return nil, err
    }

    return map[string]interface{}{
        "contents": []ResourceContent{
            {
                URI:      fmt.Sprintf("my-resource://%s", identifier),
                MIMEType: "application/json",
                Text:     string(jsonData),
            },
        },
    }, nil
}
```

## Performance Considerations

1. **Streaming:** Current implementation doesn't support streaming responses. For large outputs, consider implementing SSE transport.

2. **Concurrency:** Each request is handled in a goroutine. For high-throughput scenarios, consider implementing connection pooling or rate limiting.

3. **Memory:** Tool results are loaded entirely into memory. For large file operations, consider streaming approaches.

4. **Caching:** Session and VM state queries could benefit from caching mechanisms.

## Security Considerations

1. **Input Validation:** All tool parameters are validated before execution
2. **Sandbox Isolation:** Code execution happens in isolated Firecracker VMs
3. **Resource Limits:** CPU, memory, and timeout limits prevent resource exhaustion
4. **Network Access:** Disabled by default, must be explicitly enabled
5. **Local Only:** stdio transport means the server is only accessible locally

## Future Enhancements

Potential improvements for the MCP server:

1. **Streaming Support:** Implement streaming for long-running operations
2. **Progress Updates:** Send progress notifications during execution
3. **Batch Operations:** Support executing multiple tools in a single request
4. **Enhanced Resources:** Add more resource types (logs, metrics, etc.)
5. **Tool Chaining:** Allow tools to reference outputs from previous tools
6. **SSE Transport:** Add Server-Sent Events transport for hosted deployments

## References

- [MCP Protocol Specification](https://modelcontextprotocol.io)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [ERA Agent Main Documentation](../README.md)
- [Claude Desktop Setup Guide](../MCP_SETUP.md)
