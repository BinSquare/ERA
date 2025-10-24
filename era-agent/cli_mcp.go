package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"agent/mcp"
)

func runMCPServer(ctx context.Context, vmService *VMService, logger *Logger) error {
	logger.Info("Starting ERA Agent MCP Server", nil)

	// Create MCP server with adapters
	mcpServer := mcp.NewServer(
		&mcpLoggerAdapter{logger: logger},
		&mcpVMServiceAdapter{vmService: vmService},
	)

	// Setup context with cancellation for signal handling
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Handle signals for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		<-sigChan
		logger.Info("Received shutdown signal", nil)
		cancel()
	}()

	// Start server (blocks until context is cancelled)
	if err := mcpServer.Start(ctx); err != nil && err != context.Canceled {
		return fmt.Errorf("MCP server error: %w", err)
	}

	return nil
}

// Adapter implementations

// mcpLoggerAdapter adapts our Logger to the MCP Logger interface
type mcpLoggerAdapter struct {
	logger *Logger
}

func (a *mcpLoggerAdapter) Info(msg string, fields map[string]interface{}) {
	a.logger.Info(msg, fields)
}

func (a *mcpLoggerAdapter) Error(msg string, fields map[string]interface{}) {
	a.logger.Error(msg, fields)
}

// mcpVMServiceAdapter adapts our VMService to the MCP VMService interface
type mcpVMServiceAdapter struct {
	vmService *VMService
}

func (a *mcpVMServiceAdapter) Create(ctx context.Context, opts interface{}) (interface{}, error) {
	if a.vmService == nil {
		return nil, fmt.Errorf("VM service not available - Docker/Firecracker not running. Tools are visible for testing, but code execution requires VM infrastructure.")
	}

	optsMap, ok := opts.(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("invalid options type")
	}

	// Convert map to VMCreateOptions
	createOpts := VMCreateOptions{
		Language:    getString(optsMap, "language"),
		Image:       getString(optsMap, "image"),
		CPUCount:    getInt(optsMap, "cpu_count", 1),
		MemoryMiB:   getInt(optsMap, "memory_mib", 256),
		NetworkMode: getString(optsMap, "network_mode"),
		Persist:     getBool(optsMap, "persist", false),
	}

	record, err := a.vmService.Create(ctx, createOpts)
	if err != nil {
		return nil, err
	}

	// Convert record to map for JSON serialization
	return vmRecordToMap(record), nil
}

func (a *mcpVMServiceAdapter) Run(ctx context.Context, opts interface{}) (interface{}, error) {
	if a.vmService == nil {
		return nil, fmt.Errorf("VM service not available - Docker/Firecracker not running")
	}

	optsMap, ok := opts.(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("invalid options type")
	}

	runOpts := VMRunOptions{
		VMID:    getString(optsMap, "vmid"),
		Command: getString(optsMap, "command"),
		File:    getString(optsMap, "file"),
		Timeout: getInt(optsMap, "timeout", 30),
		Envs:    getStringMap(optsMap, "envs"),
	}

	result, err := a.vmService.Run(ctx, runOpts)
	if err != nil {
		return nil, err
	}

	// Convert result to map
	return vmRunResultToMap(result), nil
}

func (a *mcpVMServiceAdapter) Get(vmID string) (interface{}, bool) {
	if a.vmService == nil {
		return nil, false
	}
	record, ok := a.vmService.Get(vmID)
	if !ok {
		return nil, false
	}
	return vmRecordToMap(record), true
}

func (a *mcpVMServiceAdapter) List() []interface{} {
	if a.vmService == nil {
		return []interface{}{}
	}
	records := a.vmService.List()
	result := make([]interface{}, len(records))
	for i, record := range records {
		result[i] = vmRecordToMap(record)
	}
	return result
}

func (a *mcpVMServiceAdapter) Clean(ctx context.Context, vmID string, keepPersist bool) error {
	if a.vmService == nil {
		return fmt.Errorf("VM service not available")
	}
	return a.vmService.Clean(ctx, vmID, keepPersist)
}

func (a *mcpVMServiceAdapter) GetVMWorkDir(vmID string) string {
	if a.vmService == nil {
		return ""
	}
	return a.vmService.GetVMWorkDir(vmID)
}

// Helper functions for type conversion

func getString(m map[string]interface{}, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func getInt(m map[string]interface{}, key string, defaultVal int) int {
	if v, ok := m[key].(float64); ok {
		return int(v)
	}
	if v, ok := m[key].(int); ok {
		return v
	}
	return defaultVal
}

func getBool(m map[string]interface{}, key string, defaultVal bool) bool {
	if v, ok := m[key].(bool); ok {
		return v
	}
	return defaultVal
}

func getStringMap(m map[string]interface{}, key string) map[string]string {
	result := make(map[string]string)
	if v, ok := m[key].(map[string]interface{}); ok {
		for k, val := range v {
			if strVal, ok := val.(string); ok {
				result[k] = strVal
			}
		}
	}
	return result
}

func vmRecordToMap(record VMRecord) map[string]interface{} {
	return map[string]interface{}{
		"id":           record.ID,
		"language":     record.Language,
		"rootfs_image": record.RootFSImage,
		"cpu_count":    record.CPUCount,
		"memory_mib":   record.MemoryMiB,
		"network_mode": record.NetworkMode,
		"persist":      record.Persist,
		"status":       record.Status,
		"created_at":   record.CreatedAt.Format("2006-01-02T15:04:05Z"),
		"last_run_at":  record.LastRunAt.Format("2006-01-02T15:04:05Z"),
	}
}

func vmRunResultToMap(result VMRunResult) map[string]interface{} {
	// Read stdout and stderr
	stdout, _ := os.ReadFile(result.StdoutPath)
	stderr, _ := os.ReadFile(result.StderrPath)

	return map[string]interface{}{
		"exit_code": result.ExitCode,
		"stdout":    string(stdout),
		"stderr":    string(stderr),
		"duration":  result.Duration.String(),
	}
}
