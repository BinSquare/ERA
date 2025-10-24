package main

import (
	"context"
	"fmt"
	"os"
)

func main() {
	if err := run(context.Background(), os.Args[1:]); err != nil {
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string) error {
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

	cli := NewCLI(logger, vmService)
	if err := cli.Execute(ctx, remaining); err != nil {
		logger.Error("command failed", map[string]any{"error": err.Error()})
		return err
	}
	return nil
}
