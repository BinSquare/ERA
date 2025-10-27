package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

// APIServer handles HTTP API requests for the ERA Agent
type APIServer struct {
	vmService    *VMService
	logger       *Logger
	server       *http.Server
	apiKey       string
	enableAuth   bool
}

// APIRequest represents the structure for API requests
type APIRequest struct {
	Language  string `json:"language"`
	Command   string `json:"command"`
	Image     string `json:"image"`
	CPU       int    `json:"cpu"`
	Memory    int    `json:"memory"`
	Network   string `json:"network"`
	Persist   bool   `json:"persist"`
	File      string `json:"file"`
	Timeout   int    `json:"timeout"`
	VMID      string `json:"vm_id"`
	KeepPersist bool `json:"keep_persist"`
}

// APIResponse represents the structure for API responses
type APIResponse struct {
	Success    bool                   `json:"success"`
	Error      string                 `json:"error,omitempty"`
	Data       interface{}            `json:"data,omitempty"`
	StatusCode int                    `json:"status_code,omitempty"`
}

// VMInfo represents information about a VM
type VMInfo struct {
	ID          string    `json:"id"`
	Language    string    `json:"language"`
	Status      string    `json:"status"`
	CPUCount    int       `json:"cpu_count"`
	MemoryMiB   int       `json:"memory_mib"`
	NetworkMode string    `json:"network_mode"`
	Persist     bool      `json:"persist"`
	CreatedAt   time.Time `json:"created_at"`
	LastRunAt   time.Time `json:"last_run_at"`
}

// ExecutionResult represents the result of a command execution
type ExecutionResult struct {
	VMID     string `json:"vm_id"`
	ExitCode int    `json:"exit_code"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	Duration string `json:"duration"`
}

// NewAPIServer creates a new API server instance
func NewAPIServer(vmService *VMService, logger *Logger, addr string) *APIServer {
	// Check for API key in environment
	apiKey := os.Getenv("ERA_API_KEY")
	enableAuth := apiKey != ""

	api := &APIServer{
		vmService:  vmService,
		logger:     logger,
		apiKey:     apiKey,
		enableAuth: enableAuth,
	}

	mux := http.NewServeMux()
	
	// API routes
	mux.HandleFunc("/api/vm/create", api.handleCreateVM)
	mux.HandleFunc("/api/vm/execute", api.handleExecuteInVM)
	mux.HandleFunc("/api/vm/temp", api.handleRunTemp)
	mux.HandleFunc("/api/vm/list", api.handleListVMs)
	mux.HandleFunc("/api/vm/stop", api.handleStopVM)
	mux.HandleFunc("/api/vm/clean", api.handleCleanVM)
	mux.HandleFunc("/api/vm/shell", api.handleShell) // Note: shell might need websocket for interactivity
	
	// Web interface routes
	mux.HandleFunc("/", api.handleWebInterface)
	mux.HandleFunc("/index.html", api.handleWebInterface)
	mux.HandleFunc("/web/", api.handleWebAssets)

	// Create a handler that checks authentication
	// Note: We don't apply auth to web interface routes, only to API routes
	var handler http.Handler = mux
	if enableAuth {
		// Create a custom handler that applies auth only to API routes
		handler = api.requireAuthForAPI(mux)
	}

	api.server = &http.Server{
		Addr:    addr,
		Handler: handler,
	}

	return api
}

// requireAuth is a middleware that requires API key authentication
func (api *APIServer) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !api.enableAuth {
			next.ServeHTTP(w, r)
			return
		}

		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Authorization header required", http.StatusUnauthorized)
			return
		}

		// Expect "Bearer <token>" format
		if !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Authorization header must use Bearer scheme", http.StatusUnauthorized)
			return
		}

		token := strings.TrimPrefix(authHeader, "Bearer ")
		if token != api.apiKey {
			http.Error(w, "Invalid API key", http.StatusUnauthorized)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// requireAuthForAPI is a middleware that requires API key authentication only for API routes
func (api *APIServer) requireAuthForAPI(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Apply auth only to API routes (those starting with /api/)
		if strings.HasPrefix(r.URL.Path, "/api/") {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				http.Error(w, "Authorization header required for API access", http.StatusUnauthorized)
				return
			}

			// Expect "Bearer <token>" format
			if !strings.HasPrefix(authHeader, "Bearer ") {
				http.Error(w, "Authorization header must use Bearer scheme", http.StatusUnauthorized)
				return
			}

			token := strings.TrimPrefix(authHeader, "Bearer ")
			if token != api.apiKey {
				http.Error(w, "Invalid API key", http.StatusUnauthorized)
				return
			}
		}

		next.ServeHTTP(w, r)
	})
}

// handleWebInterface serves the main web interface
func (api *APIServer) handleWebInterface(w http.ResponseWriter, r *http.Request) {
	// Serve the main index.html file
	http.ServeFile(w, r, "web/index.html")
}

// handleWebAssets serves static assets from the web directory
func (api *APIServer) handleWebAssets(w http.ResponseWriter, r *http.Request) {
	// Sanitize the path to prevent directory traversal
	filePath := r.URL.Path
	if strings.HasPrefix(filePath, "/web/") {
		filePath = filePath[5:] // Remove "/web/" prefix
	} else {
		http.NotFound(w, r)
		return
	}
	
	// Prevent directory traversal
	if strings.Contains(filePath, "..") {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}
	
	// Serve the file
	http.ServeFile(w, r, "web/"+filePath)
}

// Start starts the API server
func (api *APIServer) Start() error {
	api.logger.Info("starting API server", map[string]any{"addr": api.server.Addr})
	return api.server.ListenAndServe()
}

// Stop stops the API server
func (api *APIServer) Stop(ctx context.Context) error {
	api.logger.Info("stopping API server", nil)
	return api.server.Shutdown(ctx)
}

// handleCreateVM handles VM creation requests
func (api *APIServer) handleCreateVM(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req APIRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		api.sendJSONError(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	// Set defaults
	if req.Language == "" {
		req.Language = "python"
	}
	if req.CPU == 0 {
		req.CPU = 1
	}
	if req.Memory == 0 {
		req.Memory = 256
	}
	if req.Network == "" {
		req.Network = "none"
	}
	if req.Timeout == 0 {
		req.Timeout = 30
	}

	opts := VMCreateOptions{
		Language:    req.Language,
		Image:       req.Image,
		CPUCount:    req.CPU,
		MemoryMiB:   req.Memory,
		NetworkMode: req.Network,
		Persist:     req.Persist,
	}

	record, err := api.vmService.Create(r.Context(), opts)
	if err != nil {
		api.sendJSONError(w, err.Error(), http.StatusInternalServerError)
		return
	}

	vmInfo := VMInfo{
		ID:          record.ID,
		Language:    record.Language,
		Status:      record.Status,
		CPUCount:    record.CPUCount,
		MemoryMiB:   record.MemoryMiB,
		NetworkMode: record.NetworkMode,
		Persist:     record.Persist,
		CreatedAt:   record.CreatedAt,
		LastRunAt:   record.LastRunAt,
	}

	api.sendJSONSuccess(w, vmInfo, http.StatusCreated)
}

// handleExecuteInVM handles command execution in existing VMs
func (api *APIServer) handleExecuteInVM(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req APIRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		api.sendJSONError(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	if req.VMID == "" || req.Command == "" {
		api.sendJSONError(w, "vm_id and command are required", http.StatusBadRequest)
		return
	}

	if req.Timeout == 0 {
		req.Timeout = 30
	}

	opts := VMRunOptions{
		VMID:    req.VMID,
		Command: req.Command,
		File:    req.File,
		Timeout: req.Timeout,
	}

	result, err := api.vmService.Run(r.Context(), opts)
	if err != nil {
		var runErr *VMRunError
		// Extract result from error if available
		if errors.As(err, &runErr) {
			result = runErr.Result
		}
	}

	// Read the output files
	stdoutContent := ""
	stderrContent := ""

	if result.StdoutPath != "" {
		if data, err := os.ReadFile(result.StdoutPath); err == nil {
			stdoutContent = string(data)
		}
	}
	if result.StderrPath != "" {
		if data, err := os.ReadFile(result.StderrPath); err == nil {
			stderrContent = string(data)
		}
	}

	execResult := ExecutionResult{
		VMID:     req.VMID,
		ExitCode: result.ExitCode,
		Stdout:   stdoutContent,
		Stderr:   stderrContent,
		Duration: result.Duration.String(),
	}

	if err != nil {
		api.sendJSONResponse(w, APIResponse{
			Success: false,
			Error:   err.Error(),
			Data:    execResult,
		}, http.StatusInternalServerError)
		return
	}

	api.sendJSONSuccess(w, execResult, http.StatusOK)
}

// handleRunTemp handles temporary VM execution
func (api *APIServer) handleRunTemp(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req APIRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		api.sendJSONError(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	if req.Language == "" || req.Command == "" {
		api.sendJSONError(w, "language and command are required", http.StatusBadRequest)
		return
	}

	// Set defaults
	if req.CPU == 0 {
		req.CPU = 1
	}
	if req.Memory == 0 {
		req.Memory = 256
	}
	if req.Network == "" {
		req.Network = "none"
	}
	if req.Timeout == 0 {
		req.Timeout = 30
	}

	// Create temporary VM
	opts := VMCreateOptions{
		Language:    req.Language,
		Image:       req.Image,
		CPUCount:    req.CPU,
		MemoryMiB:   req.Memory,
		NetworkMode: req.Network,
		Persist:     req.Persist,
	}

	record, err := api.vmService.Create(r.Context(), opts)
	if err != nil {
		api.sendJSONError(w, fmt.Sprintf("failed to create temporary VM: %v", err), http.StatusInternalServerError)
		return
	}

	vmID := record.ID

	// Execute command in the temporary VM
	runOpts := VMRunOptions{
		VMID:    vmID,
		Command: req.Command,
		File:    req.File,
		Timeout: req.Timeout,
	}

	runResult, err := api.vmService.Run(r.Context(), runOpts)

	// Clean up the temporary VM regardless of execution result
	cleanupErr := api.vmService.Clean(r.Context(), vmID, false)

	// Read the output files
	stdoutContent := ""
	stderrContent := ""

	if runResult.StdoutPath != "" {
		if data, err := os.ReadFile(runResult.StdoutPath); err == nil {
			stdoutContent = string(data)
		}
	}
	if runResult.StderrPath != "" {
		if data, err := os.ReadFile(runResult.StderrPath); err == nil {
			stderrContent = string(data)
		}
	}

	execResult := ExecutionResult{
		VMID:     vmID,
		ExitCode: runResult.ExitCode,
		Stdout:   stdoutContent,
		Stderr:   stderrContent,
		Duration: runResult.Duration.String(),
	}

	if err != nil {
		api.sendJSONResponse(w, APIResponse{
			Success: false,
			Error:   fmt.Sprintf("execution failed: %v, cleanup error: %v", err, cleanupErr),
			Data:    execResult,
		}, http.StatusInternalServerError)
		return
	}

	if cleanupErr != nil {
		api.logger.Warn("failed to cleanup temporary vm", map[string]any{
			"vm":    vmID,
			"error": cleanupErr.Error(),
		})
		// Don't fail the request due to cleanup error, but report it
		execResult.Stderr += fmt.Sprintf("\nWarning: VM cleanup failed: %v", cleanupErr)
	}

	api.sendJSONSuccess(w, execResult, http.StatusOK)
}

// handleListVMs handles VM listing requests
func (api *APIServer) handleListVMs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	statusFilter := r.URL.Query().Get("status")
	includeAllStr := r.URL.Query().Get("all")
	includeAll := includeAllStr == "true" || includeAllStr == "1"

	records, err := api.vmService.List(r.Context())
	if err != nil {
		api.sendJSONError(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Filter by status if specified
	if statusFilter != "" {
		filtered := make([]VMRecord, 0)
		for _, record := range records {
			if string(record.Status) == statusFilter {
				filtered = append(filtered, record)
			}
		}
		records = filtered
	}

	// If includeAll is false, only show active VMs
	if !includeAll {
		active := make([]VMRecord, 0)
		for _, record := range records {
			if record.Status == vmStatusReady || record.Status == vmStatusRunning {
				active = append(active, record)
			}
		}
		records = active
	}

	vmInfos := make([]VMInfo, len(records))
	for i, record := range records {
		vmInfos[i] = VMInfo{
			ID:          record.ID,
			Language:    record.Language,
			Status:      record.Status,
			CPUCount:    record.CPUCount,
			MemoryMiB:   record.MemoryMiB,
			NetworkMode: record.NetworkMode,
			Persist:     record.Persist,
			CreatedAt:   record.CreatedAt,
			LastRunAt:   record.LastRunAt,
		}
	}

	api.sendJSONSuccess(w, vmInfos, http.StatusOK)
}

// handleStopVM handles VM stopping requests
func (api *APIServer) handleStopVM(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req APIRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		api.sendJSONError(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	vmIDs := []string{req.VMID}
	if r.URL.Query().Get("all") == "true" {
		// Get all VM IDs
		records, err := api.vmService.List(r.Context())
		if err != nil {
			api.sendJSONError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		vmIDs = make([]string, len(records))
		for i, record := range records {
			vmIDs[i] = record.ID
		}
	}

	successCount := 0
	var errors []string

	for _, vmID := range vmIDs {
		if err := api.vmService.Stop(r.Context(), vmID); err != nil {
			errors = append(errors, fmt.Sprintf("failed to stop VM %s: %v", vmID, err))
		} else {
			successCount++
		}
	}

	if len(errors) > 0 {
		api.sendJSONResponse(w, APIResponse{
			Success: false,
			Error:   fmt.Sprintf("%d successes, %d errors. Errors: %v", successCount, len(errors), errors),
			Data: map[string]interface{}{
				"success_count": successCount,
				"error_count":   len(errors),
			},
		}, http.StatusInternalServerError)
		return
	}

	api.sendJSONSuccess(w, map[string]interface{}{
		"stopped": successCount,
	}, http.StatusOK)
}

// handleCleanVM handles VM cleanup requests
func (api *APIServer) handleCleanVM(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req APIRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		api.sendJSONError(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	vmIDs := []string{req.VMID}
	if r.URL.Query().Get("all") == "true" {
		// Get all VM IDs
		records, err := api.vmService.List(r.Context())
		if err != nil {
			api.sendJSONError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		vmIDs = make([]string, len(records))
		for i, record := range records {
			vmIDs[i] = record.ID
		}
	}

	successCount := 0
	var errors []string

	for _, vmID := range vmIDs {
		if err := api.vmService.Clean(r.Context(), vmID, req.KeepPersist); err != nil {
			errors = append(errors, fmt.Sprintf("failed to clean VM %s: %v", vmID, err))
		} else {
			successCount++
		}
	}

	if len(errors) > 0 {
		api.sendJSONResponse(w, APIResponse{
			Success: false,
			Error:   fmt.Sprintf("%d successes, %d errors. Errors: %v", successCount, len(errors), errors),
			Data: map[string]interface{}{
				"success_count": successCount,
				"error_count":   len(errors),
			},
		}, http.StatusInternalServerError)
		return
	}

	api.sendJSONSuccess(w, map[string]interface{}{
		"cleaned": successCount,
	}, http.StatusOK)
}

// handleShell would handle shell requests (though this would require WebSocket for interactivity)
func (api *APIServer) handleShell(w http.ResponseWriter, r *http.Request) {
	// Shell functionality would require WebSocket connection for interactivity
	// For now, return not implemented
	http.Error(w, "shell endpoint requires WebSocket connection, not implemented yet", http.StatusNotImplemented)
}

// sendJSONSuccess sends a successful JSON response
func (api *APIServer) sendJSONSuccess(w http.ResponseWriter, data interface{}, statusCode int) {
	api.sendJSONResponse(w, APIResponse{
		Success:    true,
		Data:       data,
		StatusCode: statusCode,
	}, statusCode)
}

// sendJSONError sends an error JSON response
func (api *APIServer) sendJSONError(w http.ResponseWriter, errorMsg string, statusCode int) {
	api.sendJSONResponse(w, APIResponse{
		Success:    false,
		Error:      errorMsg,
		StatusCode: statusCode,
	}, statusCode)
}

// sendJSONResponse sends a JSON response with the specified status code
func (api *APIServer) sendJSONResponse(w http.ResponseWriter, response APIResponse, statusCode int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	
	if err := json.NewEncoder(w).Encode(response); err != nil {
		api.logger.Error("failed to encode JSON response", map[string]any{
			"error": err.Error(),
		})
	}
}