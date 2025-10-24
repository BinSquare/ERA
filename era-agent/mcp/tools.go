package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// Tool represents an MCP tool definition
type Tool struct {
	Name        string                 `json:"name"`
	Description string                 `json:"description"`
	InputSchema map[string]interface{} `json:"inputSchema"`
}

// ToolCallRequest represents a tools/call request
type ToolCallRequest struct {
	Name      string                 `json:"name"`
	Arguments map[string]interface{} `json:"arguments,omitempty"`
}

// ToolCallResponse represents a tools/call response
type ToolCallResponse struct {
	Content []ToolContent `json:"content"`
	IsError bool          `json:"isError,omitempty"`
}

// ToolContent represents tool output content
type ToolContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// handleToolsList returns the list of available tools
func (s *Server) handleToolsList(ctx context.Context, params json.RawMessage) (interface{}, error) {
	tools := []Tool{
		{
			Name:        "era_python",
			Description: "Execute Python code in an isolated environment. To install packages, use era_shell with 'pip install <package>' first, or use a session. Example: print('Hello World')",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"code": map[string]interface{}{
						"type":        "string",
						"description": "Python code to execute. Write clean Python code without extra escaping. Newlines and indentation are preserved.",
					},
					"timeout": map[string]interface{}{
						"type":        "number",
						"description": "Execution timeout in seconds (default: 30)",
					},
				},
				"required": []string{"code"},
			},
		},
		{
			Name:        "era_node",
			Description: "Execute JavaScript/Node.js code. To install packages, use era_shell with 'npm install <package>' first, or use a session. Example: console.log('Hello World')",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"code": map[string]interface{}{
						"type":        "string",
						"description": "JavaScript code to execute. Write clean JS code without extra escaping.",
					},
					"timeout": map[string]interface{}{
						"type":        "number",
						"description": "Execution timeout in seconds (default: 30)",
					},
				},
				"required": []string{"code"},
			},
		},
		{
			Name:        "era_typescript",
			Description: "Execute TypeScript code. Example: const x: number = 5; console.log(x)",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"code": map[string]interface{}{
						"type":        "string",
						"description": "TypeScript code to execute",
					},
					"timeout": map[string]interface{}{
						"type":        "number",
						"description": "Execution timeout in seconds (default: 30)",
					},
				},
				"required": []string{"code"},
			},
		},
		{
			Name:        "era_deno",
			Description: "Execute Deno/TypeScript code. Example: console.log(Deno.version)",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"code": map[string]interface{}{
						"type":        "string",
						"description": "Deno code to execute",
					},
					"timeout": map[string]interface{}{
						"type":        "number",
						"description": "Execution timeout in seconds (default: 30)",
					},
				},
				"required": []string{"code"},
			},
		},
		{
			Name:        "era_execute_code",
			Description: "DEPRECATED: Use language-specific tools (era_python, era_node, etc.) instead. Execute code in an ephemeral environment.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"code": map[string]interface{}{
						"type":        "string",
						"description": "The code to execute",
					},
					"language": map[string]interface{}{
						"type":        "string",
						"description": "Programming language (python, node, typescript, go, deno)",
					},
					"timeout": map[string]interface{}{
						"type":        "number",
						"description": "Execution timeout in seconds (default: 30)",
					},
				},
				"required": []string{"code", "language"},
			},
		},
		{
			Name:        "era_create_session",
			Description: "Create a persistent session with file storage and state management",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Unique session identifier",
					},
					"language": map[string]interface{}{
						"type":        "string",
						"description": "Programming language (python, node, typescript, go, deno)",
					},
					"default_timeout": map[string]interface{}{
						"type":        "number",
						"description": "Default timeout for all executions in this session (seconds)",
					},
					"packages": map[string]interface{}{
						"type":        "array",
						"description": "Packages to install (npm or pip depending on language)",
						"items": map[string]interface{}{
							"type": "string",
						},
					},
				},
				"required": []string{"session_id", "language"},
			},
		},
		{
			Name:        "era_run_in_session",
			Description: "Execute code in an existing persistent session. Files and data persist between runs.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Session identifier",
					},
					"code": map[string]interface{}{
						"type":        "string",
						"description": "The code to execute",
					},
					"timeout": map[string]interface{}{
						"type":        "number",
						"description": "Execution timeout in seconds (overrides session default)",
					},
				},
				"required": []string{"session_id", "code"},
			},
		},
		{
			Name:        "era_list_sessions",
			Description: "List all active sessions",
			InputSchema: map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			},
		},
		{
			Name:        "era_get_session",
			Description: "Get detailed information about a specific session",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Session identifier",
					},
				},
				"required": []string{"session_id"},
			},
		},
		{
			Name:        "era_delete_session",
			Description: "Delete a session and clean up all associated resources",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Session identifier",
					},
				},
				"required": []string{"session_id"},
			},
		},
		{
			Name:        "era_upload_file",
			Description: "Upload a file to a persistent session",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Session identifier",
					},
					"file_path": map[string]interface{}{
						"type":        "string",
						"description": "Path where file should be stored in the session",
					},
					"content": map[string]interface{}{
						"type":        "string",
						"description": "File content (text or base64 encoded)",
					},
				},
				"required": []string{"session_id", "file_path", "content"},
			},
		},
		{
			Name:        "era_read_file",
			Description: "Read a file from a persistent session",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Session identifier",
					},
					"file_path": map[string]interface{}{
						"type":        "string",
						"description": "Path to the file in the session",
					},
				},
				"required": []string{"session_id", "file_path"},
			},
		},
		{
			Name:        "era_list_files",
			Description: "List all files in a persistent session",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Session identifier",
					},
				},
				"required": []string{"session_id"},
			},
		},
		{
			Name:        "era_shell",
			Description: "Execute shell commands. IMPORTANT: Use this to install packages BEFORE running code. Examples: 'pip install requests', 'npm install lodash', 'ls -la', 'cat file.txt'. For persistent environments, create a session first.",
			InputSchema: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"session_id": map[string]interface{}{
						"type":        "string",
						"description": "Session ID (optional - if not provided, creates an ephemeral VM)",
					},
					"command": map[string]interface{}{
						"type":        "string",
						"description": "Shell command to execute",
					},
					"timeout": map[string]interface{}{
						"type":        "number",
						"description": "Execution timeout in seconds (default: 30)",
					},
				},
				"required": []string{"command"},
			},
		},
	}

	return map[string]interface{}{
		"tools": tools,
	}, nil
}

// handleToolsCall handles tool execution
func (s *Server) handleToolsCall(ctx context.Context, params json.RawMessage) (interface{}, error) {
	var req ToolCallRequest
	if err := json.Unmarshal(params, &req); err != nil {
		return nil, fmt.Errorf("invalid tool call request: %w", err)
	}

	s.logger.Info("Executing tool", map[string]interface{}{
		"tool": req.Name,
	})

	// Route to appropriate handler
	switch req.Name {
	case "era_python":
		req.Arguments["language"] = "python"
		return s.handleExecuteCode(ctx, req.Arguments)
	case "era_node":
		req.Arguments["language"] = "node"
		return s.handleExecuteCode(ctx, req.Arguments)
	case "era_typescript":
		req.Arguments["language"] = "typescript"
		return s.handleExecuteCode(ctx, req.Arguments)
	case "era_deno":
		req.Arguments["language"] = "deno"
		return s.handleExecuteCode(ctx, req.Arguments)
	case "era_execute_code":
		return s.handleExecuteCode(ctx, req.Arguments)
	case "era_create_session":
		return s.handleCreateSession(ctx, req.Arguments)
	case "era_run_in_session":
		return s.handleRunInSession(ctx, req.Arguments)
	case "era_list_sessions":
		return s.handleListSessions(ctx, req.Arguments)
	case "era_get_session":
		return s.handleGetSessionDetails(ctx, req.Arguments)
	case "era_delete_session":
		return s.handleDeleteSession(ctx, req.Arguments)
	case "era_upload_file":
		return s.handleUploadFile(ctx, req.Arguments)
	case "era_read_file":
		return s.handleReadFile(ctx, req.Arguments)
	case "era_list_files":
		return s.handleListFiles(ctx, req.Arguments)
	case "era_shell", "era_run_shell":
		return s.handleRunShell(ctx, req.Arguments)
	default:
		return nil, fmt.Errorf("unknown tool: %s", req.Name)
	}
}

// Tool implementations

func (s *Server) handleExecuteCode(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	code, _ := args["code"].(string)
	language, _ := args["language"].(string)
	timeout, _ := args["timeout"].(float64)

	if code == "" {
		return s.errorResponse("code is required"), nil
	}
	if language == "" {
		return s.errorResponse("language is required"), nil
	}
	if timeout == 0 {
		timeout = 30
	}

	// Build the execution command for the specific language
	scriptFile, command, err := buildExecutionCommand(language)
	if err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to build command: %v", err)), nil
	}

	// Create ephemeral VM
	createOpts := map[string]interface{}{
		"language":     language,
		"cpu_count":    1,
		"memory_mib":   256,
		"network_mode": "none",
		"persist":      false,
	}

	vm, err := s.vmSvc.Create(ctx, createOpts)
	if err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to create VM: %v", err)), nil
	}

	vmMap := vm.(map[string]interface{})
	vmID := vmMap["id"].(string)

	// Get VM work directory and write code to file
	workDir := s.vmSvc.GetVMWorkDir(vmID)
	if workDir == "" {
		return s.errorResponse("Failed to get VM work directory"), nil
	}

	scriptPath := filepath.Join(workDir, scriptFile)
	if err := os.WriteFile(scriptPath, []byte(code), 0644); err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to write script file: %v", err)), nil
	}

	// Execute code with properly wrapped command
	runOpts := map[string]interface{}{
		"vmid":    vmID,
		"command": command,
		"timeout": int(timeout),
	}

	result, err := s.vmSvc.Run(ctx, runOpts)
	if err != nil {
		return s.errorResponse(fmt.Sprintf("Execution failed: %v", err)), nil
	}

	// Clean up VM
	defer s.vmSvc.Clean(ctx, vmID, false)

	resultMap := result.(map[string]interface{})

	// Format response
	output := fmt.Sprintf("Exit Code: %v\n\nStdout:\n%s\n\nStderr:\n%s",
		resultMap["exit_code"],
		resultMap["stdout"],
		resultMap["stderr"])

	return s.successResponse(output), nil
}

func (s *Server) handleCreateSession(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessionID, _ := args["session_id"].(string)
	language, _ := args["language"].(string)
	defaultTimeout, _ := args["default_timeout"].(float64)
	packages, _ := args["packages"].([]interface{})

	if sessionID == "" {
		return s.errorResponse("session_id is required"), nil
	}
	if language == "" {
		return s.errorResponse("language is required"), nil
	}

	createOpts := map[string]interface{}{
		"language":    language,
		"cpu_count":   1,
		"memory_mib":  256,
		"network_mode": "none",
		"persist":     true,
	}

	vm, err := s.vmSvc.Create(ctx, createOpts)
	if err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to create session: %v", err)), nil
	}

	vmMap := vm.(map[string]interface{})

	message := fmt.Sprintf("✅ Session created: %s\nLanguage: %s\nStatus: %s",
		vmMap["id"], vmMap["language"], vmMap["status"])

	if defaultTimeout > 0 {
		message += fmt.Sprintf("\nDefault Timeout: %.0f seconds", defaultTimeout)
	}

	if len(packages) > 0 {
		message += fmt.Sprintf("\nPackages will be installed: %v", packages)
		message += "\n\nNote: Package installation happens on first run"
	}

	return s.successResponse(message), nil
}

func (s *Server) handleRunInSession(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessionID, _ := args["session_id"].(string)
	code, _ := args["code"].(string)
	timeout, _ := args["timeout"].(float64)

	if sessionID == "" {
		return s.errorResponse("session_id is required"), nil
	}
	if code == "" {
		return s.errorResponse("code is required"), nil
	}
	if timeout == 0 {
		timeout = 30
	}

	// Check if session exists and get its language
	session, exists := s.vmSvc.Get(sessionID)
	if !exists {
		return s.errorResponse(fmt.Sprintf("Session not found: %s", sessionID)), nil
	}

	sessionMap := session.(map[string]interface{})
	language := sessionMap["language"].(string)

	// Build the execution command for the specific language
	scriptFile, command, err := buildExecutionCommand(language)
	if err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to build command: %v", err)), nil
	}

	// Get VM work directory and write code to file
	workDir := s.vmSvc.GetVMWorkDir(sessionID)
	if workDir == "" {
		return s.errorResponse("Failed to get VM work directory"), nil
	}

	scriptPath := filepath.Join(workDir, scriptFile)
	if err := os.WriteFile(scriptPath, []byte(code), 0644); err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to write script file: %v", err)), nil
	}

	// Execute code with properly wrapped command
	runOpts := map[string]interface{}{
		"vmid":    sessionID,
		"command": command,
		"timeout": int(timeout),
	}

	result, err := s.vmSvc.Run(ctx, runOpts)
	if err != nil {
		return s.errorResponse(fmt.Sprintf("Execution failed: %v", err)), nil
	}

	resultMap := result.(map[string]interface{})

	output := fmt.Sprintf("Exit Code: %v\n\nStdout:\n%s\n\nStderr:\n%s",
		resultMap["exit_code"],
		resultMap["stdout"],
		resultMap["stderr"])

	return s.successResponse(output), nil
}

func (s *Server) handleListSessions(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessions := s.vmSvc.List()

	if len(sessions) == 0 {
		return s.successResponse("No active sessions"), nil
	}

	output := fmt.Sprintf("Active Sessions: %d\n\n", len(sessions))
	for i, session := range sessions {
		sessionMap := session.(map[string]interface{})
		output += fmt.Sprintf("%d. ID: %s\n   Language: %s\n   Status: %s\n\n",
			i+1, sessionMap["id"], sessionMap["language"], sessionMap["status"])
	}

	return s.successResponse(output), nil
}

func (s *Server) handleGetSessionDetails(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessionID, _ := args["session_id"].(string)

	if sessionID == "" {
		return s.errorResponse("session_id is required"), nil
	}

	session, exists := s.vmSvc.Get(sessionID)
	if !exists {
		return s.errorResponse(fmt.Sprintf("Session not found: %s", sessionID)), nil
	}

	sessionMap := session.(map[string]interface{})

	output := fmt.Sprintf("Session: %s\nLanguage: %s\nStatus: %s\nPersistent: %v\nCPU: %v\nMemory: %v MB",
		sessionMap["id"],
		sessionMap["language"],
		sessionMap["status"],
		sessionMap["persist"],
		sessionMap["cpu_count"],
		sessionMap["memory_mib"])

	return s.successResponse(output), nil
}

func (s *Server) handleDeleteSession(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessionID, _ := args["session_id"].(string)

	if sessionID == "" {
		return s.errorResponse("session_id is required"), nil
	}

	if err := s.vmSvc.Clean(ctx, sessionID, false); err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to delete session: %v", err)), nil
	}

	return s.successResponse(fmt.Sprintf("✅ Session deleted: %s", sessionID)), nil
}

func (s *Server) handleUploadFile(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessionID, _ := args["session_id"].(string)
	filePath, _ := args["file_path"].(string)
	content, _ := args["content"].(string)

	if sessionID == "" {
		return s.errorResponse("session_id is required"), nil
	}
	if filePath == "" {
		return s.errorResponse("file_path is required"), nil
	}
	if content == "" {
		return s.errorResponse("content is required"), nil
	}

	// Get session work directory
	workDir := s.vmSvc.GetVMWorkDir(sessionID)
	if workDir == "" {
		return s.errorResponse(fmt.Sprintf("Session not found: %s", sessionID)), nil
	}

	// Write file
	fullPath := filepath.Join(workDir, filepath.Clean(filePath))
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to create directory: %v", err)), nil
	}

	if err := os.WriteFile(fullPath, []byte(content), 0644); err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to write file: %v", err)), nil
	}

	return s.successResponse(fmt.Sprintf("✅ File uploaded: %s (%d bytes)", filePath, len(content))), nil
}

func (s *Server) handleReadFile(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessionID, _ := args["session_id"].(string)
	filePath, _ := args["file_path"].(string)

	if sessionID == "" {
		return s.errorResponse("session_id is required"), nil
	}
	if filePath == "" {
		return s.errorResponse("file_path is required"), nil
	}

	// Get session work directory
	workDir := s.vmSvc.GetVMWorkDir(sessionID)
	if workDir == "" {
		return s.errorResponse(fmt.Sprintf("Session not found: %s", sessionID)), nil
	}

	// Read file
	fullPath := filepath.Join(workDir, filepath.Clean(filePath))
	content, err := os.ReadFile(fullPath)
	if err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to read file: %v", err)), nil
	}

	output := fmt.Sprintf("File: %s\nSize: %d bytes\n\nContent:\n%s", filePath, len(content), string(content))
	return s.successResponse(output), nil
}

func (s *Server) handleListFiles(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessionID, _ := args["session_id"].(string)

	if sessionID == "" {
		return s.errorResponse("session_id is required"), nil
	}

	// Get session work directory
	workDir := s.vmSvc.GetVMWorkDir(sessionID)
	if workDir == "" {
		return s.errorResponse(fmt.Sprintf("Session not found: %s", sessionID)), nil
	}

	// List files
	var files []string
	err := filepath.Walk(workDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			relPath, _ := filepath.Rel(workDir, path)
			files = append(files, fmt.Sprintf("%s (%d bytes)", relPath, info.Size()))
		}
		return nil
	})

	if err != nil {
		return s.errorResponse(fmt.Sprintf("Failed to list files: %v", err)), nil
	}

	if len(files) == 0 {
		return s.successResponse("No files in session"), nil
	}

	output := fmt.Sprintf("Files in session: %d\n\n", len(files))
	for i, file := range files {
		output += fmt.Sprintf("%d. %s\n", i+1, file)
	}

	return s.successResponse(output), nil
}

func (s *Server) handleRunShell(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	sessionID, _ := args["session_id"].(string)
	command, _ := args["command"].(string)
	timeout, _ := args["timeout"].(float64)

	if command == "" {
		return s.errorResponse("command is required"), nil
	}
	if timeout == 0 {
		timeout = 30
	}

	var vmID string
	var isEphemeral bool

	// If session_id provided, use that session; otherwise create ephemeral VM
	if sessionID != "" {
		// Check if session exists
		_, exists := s.vmSvc.Get(sessionID)
		if !exists {
			return s.errorResponse(fmt.Sprintf("Session not found: %s", sessionID)), nil
		}
		vmID = sessionID
		isEphemeral = false
	} else {
		// Create ephemeral VM for one-off shell command (use Python as default language)
		createOpts := map[string]interface{}{
			"language":     "python",
			"cpu_count":    1,
			"memory_mib":   256,
			"network_mode": "none",
			"persist":      false,
		}

		vm, err := s.vmSvc.Create(ctx, createOpts)
		if err != nil {
			return s.errorResponse(fmt.Sprintf("Failed to create VM: %v", err)), nil
		}

		vmMap := vm.(map[string]interface{})
		vmID = vmMap["id"].(string)
		isEphemeral = true
	}

	// Execute shell command directly (no language wrapping needed)
	runOpts := map[string]interface{}{
		"vmid":    vmID,
		"command": command,
		"timeout": int(timeout),
	}

	result, err := s.vmSvc.Run(ctx, runOpts)
	if err != nil {
		// Clean up ephemeral VM if it failed
		if isEphemeral {
			s.vmSvc.Clean(ctx, vmID, false)
		}
		return s.errorResponse(fmt.Sprintf("Command execution failed: %v", err)), nil
	}

	// Clean up ephemeral VM after execution
	if isEphemeral {
		defer s.vmSvc.Clean(ctx, vmID, false)
	}

	resultMap := result.(map[string]interface{})

	output := fmt.Sprintf("Exit Code: %v\n\nStdout:\n%s\n\nStderr:\n%s",
		resultMap["exit_code"],
		resultMap["stdout"],
		resultMap["stderr"])

	return s.successResponse(output), nil
}

// Helper methods

func (s *Server) successResponse(text string) interface{} {
	return ToolCallResponse{
		Content: []ToolContent{
			{
				Type: "text",
				Text: text,
			},
		},
		IsError: false,
	}
}

func (s *Server) errorResponse(text string) interface{} {
	return ToolCallResponse{
		Content: []ToolContent{
			{
				Type: "text",
				Text: "❌ Error: " + text,
			},
		},
		IsError: true,
	}
}

// buildExecutionCommand wraps code in the appropriate runtime command
// Returns (scriptFilename, command, error) where scriptFilename is relative to workdir
func buildExecutionCommand(language string) (string, string, error) {
	// Generate a unique script filename (relative to VM work directory)
	timestamp := time.Now().UnixNano()

	switch language {
	case "python":
		scriptFile := fmt.Sprintf("era_script_%d.py", timestamp)
		command := fmt.Sprintf("python3 %s", scriptFile)
		return scriptFile, command, nil
	case "node", "javascript":
		scriptFile := fmt.Sprintf("era_script_%d.js", timestamp)
		command := fmt.Sprintf("node %s", scriptFile)
		return scriptFile, command, nil
	case "typescript":
		scriptFile := fmt.Sprintf("era_script_%d.ts", timestamp)
		command := fmt.Sprintf("ts-node %s", scriptFile)
		return scriptFile, command, nil
	case "deno":
		scriptFile := fmt.Sprintf("era_script_%d.ts", timestamp)
		command := fmt.Sprintf("deno run %s", scriptFile)
		return scriptFile, command, nil
	case "go":
		scriptFile := fmt.Sprintf("era_script_%d.go", timestamp)
		command := fmt.Sprintf("go run %s", scriptFile)
		return scriptFile, command, nil
	default:
		return "", "", fmt.Errorf("unsupported language: %s", language)
	}
}
