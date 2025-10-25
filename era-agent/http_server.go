package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type HTTPServer struct {
	vmService *VMService
	logger    *Logger
	port      string
}

func NewHTTPServer(vmService *VMService, logger *Logger, port string) *HTTPServer {
	if port == "" {
		port = "8787"
	}
	return &HTTPServer{
		vmService: vmService,
		logger:    logger,
		port:      port,
	}
}

func (s *HTTPServer) Start(ctx context.Context) error {
	mux := http.NewServeMux()

	// Health check
	mux.HandleFunc("/health", s.handleHealth)

	// VM operations
	mux.HandleFunc("/api/vm", s.handleVMRoot)
	mux.HandleFunc("/api/vm/", s.handleVMByID)
	mux.HandleFunc("/api/vms", s.handleVMList)

	server := &http.Server{
		Addr:    ":" + s.port,
		Handler: corsMiddleware(loggingMiddleware(s.logger, mux)),
	}

	s.logger.Info("http server starting", map[string]any{"port": s.port})

	errCh := make(chan error, 1)
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		s.logger.Info("shutting down http server", nil)
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	}
}

// Health check endpoint
func (s *HTTPServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]any{
		"status": "healthy",
		"time":   time.Now().UTC().Format(time.RFC3339),
	})
}

// POST /api/vm - Create VM
func (s *HTTPServer) handleVMRoot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Language    string `json:"language"`
		Image       string `json:"image"`
		CPUCount    int    `json:"cpu_count"`
		MemoryMiB   int    `json:"memory_mib"`
		NetworkMode string `json:"network_mode"`
		Persist     bool   `json:"persist"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	// Validate required fields
	if req.Language == "" {
		s.writeError(w, http.StatusBadRequest, "language is required", nil)
		return
	}
	if req.CPUCount <= 0 {
		req.CPUCount = 1
	}
	if req.MemoryMiB <= 0 {
		req.MemoryMiB = 256
	}
	if req.NetworkMode == "" {
		req.NetworkMode = "none"
	}

	opts := VMCreateOptions{
		Language:    req.Language,
		Image:       req.Image,
		CPUCount:    req.CPUCount,
		MemoryMiB:   req.MemoryMiB,
		NetworkMode: req.NetworkMode,
		Persist:     req.Persist,
	}

	record, err := s.vmService.Create(r.Context(), opts)
	if err != nil {
		s.logger.Error("vm create failed", map[string]any{"error": err.Error()})
		s.writeError(w, http.StatusInternalServerError, "failed to create vm", err)
		return
	}

	s.logger.Info("vm created via http", map[string]any{"id": record.ID})
	s.writeJSON(w, http.StatusCreated, s.vmRecordToResponse(record))
}

// Handle /api/vm/{id} endpoints
func (s *HTTPServer) handleVMByID(w http.ResponseWriter, r *http.Request) {
	// Extract VM ID from path
	path := strings.TrimPrefix(r.URL.Path, "/api/vm/")
	parts := strings.Split(path, "/")
	if len(parts) == 0 || parts[0] == "" {
		http.Error(w, "vm id required", http.StatusBadRequest)
		return
	}

	vmID := parts[0]

	// Route based on method and sub-path
	switch r.Method {
	case http.MethodGet:
		if len(parts) > 1 && parts[1] == "files" {
			// GET /api/vm/{id}/files or GET /api/vm/{id}/files/{path}
			if len(parts) == 2 {
				s.handleVMFilesList(w, r, vmID)
			} else {
				filePath := strings.Join(parts[2:], "/")
				s.handleVMFileDownload(w, r, vmID, filePath)
			}
		} else {
			s.handleVMGet(w, r, vmID)
		}
	case http.MethodPut:
		if len(parts) > 1 && parts[1] == "files" && len(parts) > 2 {
			// PUT /api/vm/{id}/files/{path}
			filePath := strings.Join(parts[2:], "/")
			s.handleVMFileUpload(w, r, vmID, filePath)
		} else {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	case http.MethodDelete:
		if len(parts) > 1 && parts[1] == "files" && len(parts) > 2 {
			// DELETE /api/vm/{id}/files/{path}
			filePath := strings.Join(parts[2:], "/")
			s.handleVMFileDelete(w, r, vmID, filePath)
		} else {
			s.handleVMDelete(w, r, vmID)
		}
	case http.MethodPost:
		if len(parts) > 1 {
			switch parts[1] {
			case "run":
				s.handleVMRun(w, r, vmID)
			case "stream":
				s.handleVMRunStream(w, r, vmID)
			case "stop":
				s.handleVMStop(w, r, vmID)
			default:
				http.Error(w, "unknown action", http.StatusNotFound)
			}
		} else {
			http.Error(w, "action required", http.StatusBadRequest)
		}
	case http.MethodPatch:
		s.handleVMUpdate(w, r, vmID)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

// GET /api/vm/{id} - Get VM details
func (s *HTTPServer) handleVMGet(w http.ResponseWriter, r *http.Request, vmID string) {
	record, ok := s.vmService.Get(vmID)
	if !ok {
		s.writeError(w, http.StatusNotFound, "vm not found", nil)
		return
	}

	s.writeJSON(w, http.StatusOK, s.vmRecordToResponse(record))
}

// POST /api/vm/{id}/run - Run code in VM
func (s *HTTPServer) handleVMRun(w http.ResponseWriter, r *http.Request, vmID string) {
	var req struct {
		Command string            `json:"command"`
		File    string            `json:"file"`
		Timeout int               `json:"timeout"`
		Envs    map[string]string `json:"envs"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	if req.Command == "" {
		s.writeError(w, http.StatusBadRequest, "command is required", nil)
		return
	}
	if req.Timeout <= 0 {
		req.Timeout = 30
	}

	opts := VMRunOptions{
		VMID:    vmID,
		Command: req.Command,
		File:    req.File,
		Timeout: req.Timeout,
		Envs:    req.Envs,
	}

	result, err := s.vmService.Run(r.Context(), opts)
	if err != nil {
		s.logger.Error("vm run failed", map[string]any{"vm": vmID, "error": err.Error()})
		s.writeError(w, http.StatusInternalServerError, "failed to run command", err)
		return
	}

	// Read stdout and stderr files
	stdout, _ := os.ReadFile(result.StdoutPath)
	stderr, _ := os.ReadFile(result.StderrPath)

	s.writeJSON(w, http.StatusOK, map[string]any{
		"exit_code": result.ExitCode,
		"stdout":    string(stdout),
		"stderr":    string(stderr),
		"duration":  result.Duration.String(),
	})
}

// POST /api/vm/{id}/stream - Run code with streaming output (SSE)
func (s *HTTPServer) handleVMRunStream(w http.ResponseWriter, r *http.Request, vmID string) {
	var req struct {
		Command string            `json:"command"`
		File    string            `json:"file"`
		Timeout int               `json:"timeout"`
		Envs    map[string]string `json:"envs"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	if req.Command == "" {
		s.writeError(w, http.StatusBadRequest, "command is required", nil)
		return
	}
	if req.Timeout <= 0 {
		req.Timeout = 30
	}

	// Set headers for SSE
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	// Create event channel
	eventChan := make(chan StreamEvent, 100)

	// Start streaming execution in goroutine
	opts := VMRunOptions{
		VMID:    vmID,
		Command: req.Command,
		File:    req.File,
		Timeout: req.Timeout,
		Envs:    req.Envs,
	}

	go s.vmService.RunStreaming(r.Context(), opts, eventChan)

	// Flush initial response
	if flusher, ok := w.(http.Flusher); ok {
		flusher.Flush()
	}

	// Stream events as they arrive
	for event := range eventChan {
		eventJSON, err := json.Marshal(event)
		if err != nil {
			s.logger.Error("failed to marshal event", map[string]any{"error": err.Error()})
			continue
		}

		// Write SSE format: "event: message\ndata: {json}\n\n"
		fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event.Type, string(eventJSON))

		// Flush after each event
		if flusher, ok := w.(http.Flusher); ok {
			flusher.Flush()
		}
	}
}

// POST /api/vm/{id}/stop - Stop VM
func (s *HTTPServer) handleVMStop(w http.ResponseWriter, r *http.Request, vmID string) {
	if err := s.vmService.Stop(r.Context(), vmID); err != nil {
		s.logger.Error("vm stop failed", map[string]any{"vm": vmID, "error": err.Error()})
		s.writeError(w, http.StatusInternalServerError, "failed to stop vm", err)
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]any{
		"status":  "stopped",
		"vm_id":   vmID,
		"message": "VM stopped successfully",
	})
}

// DELETE /api/vm/{id} - Clean up VM
func (s *HTTPServer) handleVMDelete(w http.ResponseWriter, r *http.Request, vmID string) {
	keepPersist := r.URL.Query().Get("keep_persist") == "true"

	if err := s.vmService.Clean(r.Context(), vmID, keepPersist); err != nil {
		s.logger.Error("vm clean failed", map[string]any{"vm": vmID, "error": err.Error()})
		s.writeError(w, http.StatusInternalServerError, "failed to clean vm", err)
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]any{
		"status":  "deleted",
		"vm_id":   vmID,
		"message": "VM cleaned successfully",
	})
}

// PATCH /api/vm/{id} - Update VM metadata
func (s *HTTPServer) handleVMUpdate(w http.ResponseWriter, r *http.Request, vmID string) {
	var req struct {
		NetworkMode *string `json:"network_mode"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		s.writeError(w, http.StatusBadRequest, "invalid request body", err)
		return
	}

	// Get existing record
	record, ok := s.vmService.Get(vmID)
	if !ok {
		s.writeError(w, http.StatusNotFound, "vm not found", nil)
		return
	}

	// Apply updates
	updated := false
	if req.NetworkMode != nil {
		// Validate network mode
		validModes := map[string]bool{"none": true, "host": true, "bridge": true}
		if !validModes[*req.NetworkMode] {
			s.writeError(w, http.StatusBadRequest, "invalid network_mode, must be 'none', 'host', or 'bridge'", nil)
			return
		}
		record.NetworkMode = *req.NetworkMode
		updated = true
	}

	if !updated {
		s.writeError(w, http.StatusBadRequest, "no valid fields to update", nil)
		return
	}

	// Save updated record
	if err := s.vmService.Update(record); err != nil {
		s.logger.Error("vm update failed", map[string]any{"vm": vmID, "error": err.Error()})
		s.writeError(w, http.StatusInternalServerError, "failed to update vm", err)
		return
	}

	s.logger.Info("vm updated via http", map[string]any{"id": vmID})
	s.writeJSON(w, http.StatusOK, s.vmRecordToResponse(record))
}

// GET /api/vms - List all VMs
func (s *HTTPServer) handleVMList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	records := s.vmService.List()
	vms := make([]map[string]any, len(records))
	for i, record := range records {
		vms[i] = s.vmRecordToResponse(record)
	}

	s.writeJSON(w, http.StatusOK, map[string]any{
		"vms":   vms,
		"count": len(vms),
	})
}

// GET /api/vm/{id}/files - List files in VM
func (s *HTTPServer) handleVMFilesList(w http.ResponseWriter, r *http.Request, vmID string) {
	// Verify VM exists
	_, ok := s.vmService.Get(vmID)
	if !ok {
		s.writeError(w, http.StatusNotFound, "vm not found", nil)
		return
	}

	// Get VM working directory
	workDir := s.vmService.GetVMWorkDir(vmID)
	if workDir == "" {
		s.writeError(w, http.StatusInternalServerError, "vm work directory not found", nil)
		return
	}

	// List files recursively
	files, err := listFilesRecursive(workDir, "")
	if err != nil {
		s.writeError(w, http.StatusInternalServerError, "failed to list files", err)
		return
	}

	s.writeJSON(w, http.StatusOK, map[string]any{
		"files": files,
		"count": len(files),
	})
}

// GET /api/vm/{id}/files/{path} - Download file from VM
func (s *HTTPServer) handleVMFileDownload(w http.ResponseWriter, r *http.Request, vmID, filePath string) {
	// Verify VM exists
	_, ok := s.vmService.Get(vmID)
	if !ok {
		s.writeError(w, http.StatusNotFound, "vm not found", nil)
		return
	}

	// Get VM working directory
	workDir := s.vmService.GetVMWorkDir(vmID)
	if workDir == "" {
		s.writeError(w, http.StatusInternalServerError, "vm work directory not found", nil)
		return
	}

	// Construct full path (prevent directory traversal)
	fullPath := filepath.Join(workDir, filepath.Clean("/"+filePath))
	if !strings.HasPrefix(fullPath, workDir) {
		s.writeError(w, http.StatusBadRequest, "invalid file path", nil)
		return
	}

	// Read file
	content, err := os.ReadFile(fullPath)
	if err != nil {
		if os.IsNotExist(err) {
			s.writeError(w, http.StatusNotFound, "file not found", err)
		} else {
			s.writeError(w, http.StatusInternalServerError, "failed to read file", err)
		}
		return
	}

	// Return file content
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filepath.Base(filePath)))
	w.Write(content)
}

// PUT /api/vm/{id}/files/{path} - Upload file to VM
func (s *HTTPServer) handleVMFileUpload(w http.ResponseWriter, r *http.Request, vmID, filePath string) {
	// Verify VM exists
	_, ok := s.vmService.Get(vmID)
	if !ok {
		s.writeError(w, http.StatusNotFound, "vm not found", nil)
		return
	}

	// Get VM working directory
	workDir := s.vmService.GetVMWorkDir(vmID)
	if workDir == "" {
		s.writeError(w, http.StatusInternalServerError, "vm work directory not found", nil)
		return
	}

	// Construct full path (prevent directory traversal)
	fullPath := filepath.Join(workDir, filepath.Clean("/"+filePath))
	if !strings.HasPrefix(fullPath, workDir) {
		s.writeError(w, http.StatusBadRequest, "invalid file path", nil)
		return
	}

	// Read request body
	content, err := io.ReadAll(r.Body)
	if err != nil {
		s.writeError(w, http.StatusBadRequest, "failed to read body", err)
		return
	}

	// Ensure directory exists
	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		s.writeError(w, http.StatusInternalServerError, "failed to create directory", err)
		return
	}

	// Write file
	if err := os.WriteFile(fullPath, content, 0644); err != nil {
		s.writeError(w, http.StatusInternalServerError, "failed to write file", err)
		return
	}

	s.logger.Info("file uploaded to vm", map[string]any{"vm": vmID, "path": filePath, "size": len(content)})

	s.writeJSON(w, http.StatusOK, map[string]any{
		"path": filePath,
		"size": len(content),
	})
}

// DELETE /api/vm/{id}/files/{path} - Delete file from VM
func (s *HTTPServer) handleVMFileDelete(w http.ResponseWriter, r *http.Request, vmID, filePath string) {
	// Verify VM exists
	_, ok := s.vmService.Get(vmID)
	if !ok {
		s.writeError(w, http.StatusNotFound, "vm not found", nil)
		return
	}

	// Get VM working directory
	workDir := s.vmService.GetVMWorkDir(vmID)
	if workDir == "" {
		s.writeError(w, http.StatusInternalServerError, "vm work directory not found", nil)
		return
	}

	// Construct full path (prevent directory traversal)
	fullPath := filepath.Join(workDir, filepath.Clean("/"+filePath))
	if !strings.HasPrefix(fullPath, workDir) {
		s.writeError(w, http.StatusBadRequest, "invalid file path", nil)
		return
	}

	// Delete file
	if err := os.Remove(fullPath); err != nil {
		if os.IsNotExist(err) {
			s.writeError(w, http.StatusNotFound, "file not found", err)
		} else {
			s.writeError(w, http.StatusInternalServerError, "failed to delete file", err)
		}
		return
	}

	s.logger.Info("file deleted from vm", map[string]any{"vm": vmID, "path": filePath})

	s.writeJSON(w, http.StatusOK, map[string]any{
		"deleted": filePath,
	})
}

// Helper: Convert VMRecord to HTTP response
func (s *HTTPServer) vmRecordToResponse(record VMRecord) map[string]any {
	return map[string]any{
		"id":           record.ID,
		"language":     record.Language,
		"rootfs_image": record.RootFSImage,
		"cpu_count":    record.CPUCount,
		"memory_mib":   record.MemoryMiB,
		"network_mode": record.NetworkMode,
		"persist":      record.Persist,
		"status":       record.Status,
		"created_at":   record.CreatedAt.Format(time.RFC3339),
		"last_run_at":  record.LastRunAt.Format(time.RFC3339),
	}
}

// Helper: Write JSON response
func (s *HTTPServer) writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(data); err != nil {
		s.logger.Error("failed to encode json", map[string]any{"error": err.Error()})
	}
}

// Helper: Write error response
func (s *HTTPServer) writeError(w http.ResponseWriter, status int, message string, err error) {
	response := map[string]any{
		"error":   message,
		"status":  status,
		"message": message,
	}
	if err != nil {
		response["details"] = err.Error()
	}
	s.writeJSON(w, status, response)
}

// Middleware: CORS
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// Middleware: Request logging
func loggingMiddleware(logger *Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Wrap response writer to capture status code
		wrapped := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(wrapped, r)

		logger.Info("http request", map[string]any{
			"method":   r.Method,
			"path":     r.URL.Path,
			"status":   wrapped.statusCode,
			"duration": time.Since(start).String(),
			"ip":       r.RemoteAddr,
		})
	})
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

// ReadBody is a helper to read and restore request body
func ReadBody(r *http.Request) ([]byte, error) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		return nil, err
	}
	r.Body.Close()
	return body, nil
}

// Helper: List files recursively
type FileInfo struct {
	Path  string `json:"path"`
	Size  int64  `json:"size"`
	IsDir bool   `json:"is_dir"`
}

func listFilesRecursive(baseDir, relPath string) ([]FileInfo, error) {
	var files []FileInfo
	fullPath := filepath.Join(baseDir, relPath)

	entries, err := os.ReadDir(fullPath)
	if err != nil {
		return nil, err
	}

	for _, entry := range entries {
		entryRelPath := filepath.Join(relPath, entry.Name())

		info, err := entry.Info()
		if err != nil {
			continue
		}

		if entry.IsDir() {
			// Recursively list subdirectory
			subFiles, err := listFilesRecursive(baseDir, entryRelPath)
			if err == nil {
				files = append(files, subFiles...)
			}
		} else {
			files = append(files, FileInfo{
				Path:  entryRelPath,
				Size:  info.Size(),
				IsDir: false,
			})
		}
	}

	return files, nil
}
