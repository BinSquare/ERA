package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func main() {
	if err := run(context.Background(), os.Args[1:]); err != nil {
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string) error {
	// Check if another instance is running
	if err := checkForRunningInstance(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return err
	}

	opts, remaining, err := parseGlobalOptions(args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return err
	}

	logger, err := NewLogger(opts.LogLevel, opts.LogFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return err
	}
	defer func() {
		if cerr := logger.Close(); cerr != nil {
			fmt.Fprintf(os.Stderr, "error closing logger: %v\n", cerr)
		}
	}()

	vmService, err := NewVMService(logger, opts.VMRuntime)
	if err != nil {
		logger.Error("failed to init vm service", map[string]any{"error": err.Error()})
		return err
	}
	defer func() {
		if cerr := vmService.Close(); cerr != nil {
			logger.Error("failed to close vm store", map[string]any{"error": cerr.Error()})
		}
	}()

	// Check if we should run as an API server
	if len(args) > 0 && strings.ToLower(args[0]) == "server" {
		serverAddr := ":8080" // Default address
		// Check for --addr flag in remaining args
		for i := 0; i < len(remaining); i++ {
			if remaining[i] == "--addr" && i+1 < len(remaining) {
				serverAddr = remaining[i+1]
				break
			}
		}

		apiServer := NewAPIServer(vmService, logger, serverAddr)
		return apiServer.Start()
	}

	// Default to CLI mode
	cli := NewCLI(logger, vmService)
	if err := cli.Execute(ctx, remaining); err != nil {
		logger.Error("command failed", map[string]any{"error": err.Error()})
		return err
	}
	return nil
}

// checkForRunningInstance checks if another instance of the agent is already running
func checkForRunningInstance() error {
	// Use ps with full command line to identify agent processes
	cmd := exec.Command("ps", "-eo", "pid,command")
	output, err := cmd.Output()
	if err != nil {
		// If ps fails, we can't check, so assume it's safe to proceed
		return nil
	}

	psOutput := string(output)
	lines := strings.Split(psOutput, "\n")
	currentPID := os.Getpid()
	
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		
		// Split the line to get PID and full command
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		
		pidStr := fields[0]
		
		// Skip header line
		if pidStr == "PID" {
			continue
		}
		
		// Reconstruct the command by joining the remaining fields
		command := strings.Join(fields[1:], " ")
		
		// Convert PID to integer to check against current process
		if pidStr == fmt.Sprintf("%d", currentPID) {
			continue
		}
		
		// Check if the command contains "agent" and ends with "agent" as an executable
		// This distinguishes from other processes that might contain "agent" like "logioptionsplus_agent"
		// Also look for common execution patterns
		if strings.Contains(command, "agent") {
			// Check if the executable part of the command is "agent" or contains "/agent"
			// Split by spaces and look for the executable name
			cmdParts := strings.Fields(command)
			if len(cmdParts) > 0 {
				executable := cmdParts[0]
				// Check if the executable is the agent binary (has "agent" as the final part of the path)
				if strings.Contains(executable, "/agent") || executable == "agent" || executable == "./agent" {
					return fmt.Errorf("another instance of agent is already running with PID %s", pidStr)
				}
			}
		}
	}

	return nil
}
