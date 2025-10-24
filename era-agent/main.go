package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
)

func main() {
	if err := run(context.Background(), os.Args[1:]); err != nil {
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string) error {
	// Check if we should run as HTTP server
	mode := strings.ToLower(strings.TrimSpace(os.Getenv("AGENT_MODE")))

	opts, remaining, err := parseGlobalOptions(args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return err
	}

	logger := NewLogger(opts.LogLevel)

	// Check if we're running MCP mode first
	isMCPMode := len(remaining) > 0 && remaining[0] == "mcp"

	vmService, err := NewVMService(logger)
	if err != nil {
		if isMCPMode {
			// In MCP mode, warn but continue - allows testing tools without VM infrastructure
			logger.Error("VM service init failed - MCP server will start but code execution won't work", map[string]any{
				"error": err.Error(),
				"help":  "To actually run code, ensure Docker/Firecracker is available",
			})
			// Use a stub VM service for MCP mode
			vmService = nil
		} else {
			// For other modes, VM service is required
			logger.Error("failed to init vm service", map[string]any{"error": err.Error()})
			return err
		}
	}
	defer func() {
		if vmService != nil {
			if cerr := vmService.Close(); cerr != nil {
				logger.Error("failed to close vm store", map[string]any{"error": cerr.Error()})
			}
		}
	}()

	// Run as HTTP server if mode is set or if first arg is "serve"
	if mode == "http" || mode == "server" || (len(remaining) > 0 && remaining[0] == "serve") {
		return runHTTPServer(ctx, vmService, logger)
	}

	// Otherwise run as CLI
	cli := NewCLI(logger, vmService)
	if err := cli.Execute(ctx, remaining); err != nil {
		logger.Error("command failed", map[string]any{"error": err.Error()})
		return err
	}
	return nil
}

func runHTTPServer(ctx context.Context, vmService *VMService, logger *Logger) error {
	// Setup signal handling for graceful shutdown
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)

	go func() {
		<-sigCh
		logger.Info("received shutdown signal", nil)
		cancel()
	}()

	port := getenvOrDefault("PORT", "8787")
	server := NewHTTPServer(vmService, logger, port)

	logger.Info("starting agent in http server mode", map[string]any{
		"port": port,
		"env":  "Set AGENT_MODE=http or run './agent serve' to start server",
	})

	return server.Start(ctx)
}
