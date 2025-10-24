package mcp

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sync"
)

// JSONRPCRequest represents an MCP request following JSON-RPC 2.0
type JSONRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      interface{}     `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

// JSONRPCResponse represents an MCP response following JSON-RPC 2.0
type JSONRPCResponse struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      interface{} `json:"id,omitempty"`
	Result  interface{} `json:"result,omitempty"`
	Error   *RPCError   `json:"error,omitempty"`
}

// RPCError represents a JSON-RPC error
type RPCError struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// Server represents the MCP server
type Server struct {
	mu       sync.RWMutex
	handlers map[string]Handler
	logger   Logger
	vmSvc    VMService
}

// Handler is a function that handles MCP requests
type Handler func(ctx context.Context, params json.RawMessage) (interface{}, error)

// Logger interface for logging
type Logger interface {
	Info(msg string, fields map[string]interface{})
	Error(msg string, fields map[string]interface{})
}

// VMService interface for VM operations
type VMService interface {
	Create(ctx context.Context, opts interface{}) (interface{}, error)
	Run(ctx context.Context, opts interface{}) (interface{}, error)
	Get(vmID string) (interface{}, bool)
	List() []interface{}
	Clean(ctx context.Context, vmID string, keepPersist bool) error
	GetVMWorkDir(vmID string) string
}

// NewServer creates a new MCP server
func NewServer(logger Logger, vmSvc VMService) *Server {
	s := &Server{
		handlers: make(map[string]Handler),
		logger:   logger,
		vmSvc:    vmSvc,
	}

	// Register MCP protocol handlers
	s.RegisterHandler("initialize", s.handleInitialize)
	s.RegisterHandler("tools/list", s.handleToolsList)
	s.RegisterHandler("tools/call", s.handleToolsCall)
	s.RegisterHandler("resources/list", s.handleResourcesList)
	s.RegisterHandler("resources/read", s.handleResourcesRead)

	return s
}

// RegisterHandler registers a request handler
func (s *Server) RegisterHandler(method string, handler Handler) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.handlers[method] = handler
}

// Start starts the MCP server reading from stdin and writing to stdout
func (s *Server) Start(ctx context.Context) error {
	s.logger.Info("MCP server starting", map[string]interface{}{
		"protocol": "stdio",
	})

	reader := bufio.NewReader(os.Stdin)
	writer := bufio.NewWriter(os.Stdout)

	// Process requests in a loop
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		// Read line from stdin
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return fmt.Errorf("failed to read request: %w", err)
		}

		// Parse request
		var req JSONRPCRequest
		if err := json.Unmarshal(line, &req); err != nil {
			s.writeError(writer, nil, -32700, "Parse error", err)
			continue
		}

		// Handle request
		go s.handleRequest(ctx, writer, &req)
	}
}

// handleRequest processes a single request
func (s *Server) handleRequest(ctx context.Context, writer *bufio.Writer, req *JSONRPCRequest) {
	s.logger.Info("Received request", map[string]interface{}{
		"method": req.Method,
		"id":     req.ID,
	})

	// Get handler
	s.mu.RLock()
	handler, ok := s.handlers[req.Method]
	s.mu.RUnlock()

	if !ok {
		// If this is a notification (no ID), just ignore it
		if req.ID == nil {
			s.logger.Info("Ignoring notification", map[string]interface{}{
				"method": req.Method,
			})
			return
		}
		s.writeError(writer, req.ID, -32601, "Method not found", nil)
		return
	}

	// Execute handler
	result, err := handler(ctx, req.Params)
	if err != nil {
		s.writeError(writer, req.ID, -32603, "Internal error", err)
		return
	}

	// Write response
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result:  result,
	}

	if err := s.writeResponse(writer, &resp); err != nil {
		s.logger.Error("Failed to write response", map[string]interface{}{
			"error": err.Error(),
		})
	}
}

// writeResponse writes a JSON-RPC response
func (s *Server) writeResponse(writer *bufio.Writer, resp *JSONRPCResponse) error {
	data, err := json.Marshal(resp)
	if err != nil {
		return fmt.Errorf("failed to marshal response: %w", err)
	}

	if _, err := writer.Write(data); err != nil {
		return fmt.Errorf("failed to write response: %w", err)
	}

	if err := writer.WriteByte('\n'); err != nil {
		return fmt.Errorf("failed to write newline: %w", err)
	}

	if err := writer.Flush(); err != nil {
		return fmt.Errorf("failed to flush: %w", err)
	}

	return nil
}

// writeError writes a JSON-RPC error response
func (s *Server) writeError(writer *bufio.Writer, id interface{}, code int, message string, err error) {
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Error: &RPCError{
			Code:    code,
			Message: message,
		},
	}

	if err != nil {
		resp.Error.Data = err.Error()
	}

	if writeErr := s.writeResponse(writer, &resp); writeErr != nil {
		s.logger.Error("Failed to write error response", map[string]interface{}{
			"error": writeErr.Error(),
		})
	}
}

// handleInitialize handles the initialize request
func (s *Server) handleInitialize(ctx context.Context, params json.RawMessage) (interface{}, error) {
	// Parse the client's protocol version
	var initParams struct {
		ProtocolVersion string `json:"protocolVersion"`
	}
	if err := json.Unmarshal(params, &initParams); err == nil && initParams.ProtocolVersion != "" {
		// Echo back the client's protocol version if provided
		return map[string]interface{}{
			"protocolVersion": initParams.ProtocolVersion,
			"capabilities": map[string]interface{}{
				"tools": map[string]interface{}{},
				"resources": map[string]interface{}{
					"subscribe":   true,
					"listChanged": true,
				},
			},
			"serverInfo": map[string]interface{}{
				"name":    "era-agent-mcp",
				"version": "1.0.0",
			},
		}, nil
	}

	// Fallback to default version
	return map[string]interface{}{
		"protocolVersion": "2024-11-05",
		"capabilities": map[string]interface{}{
			"tools": map[string]interface{}{},
			"resources": map[string]interface{}{
				"subscribe":   true,
				"listChanged": true,
			},
		},
		"serverInfo": map[string]interface{}{
			"name":    "era-agent-mcp",
			"version": "1.0.0",
		},
	}, nil
}
