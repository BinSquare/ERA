package main

import (
	"context"
	"errors"
	"flag"
	"io"
)

func (c *CLI) executeVM(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return errors.New("vm subcommand required")
	}

	switch args[0] {
	case "create":
		return c.handleVMCreate(ctx, args[1:])
	case "run":
		return c.handleVMRun(ctx, args[1:])
	case "stop":
		return c.handleVMStop(ctx, args[1:])
	case "clean":
		return c.handleVMClean(ctx, args[1:])
	default:
		return errors.New("unknown vm subcommand")
	}
}

func (c *CLI) handleVMCreate(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm create", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	language := fs.String("language", "", "guest language runtime")
	image := fs.String("image", "", "override rootfs image")
	cpu := fs.Int("cpu", 1, "virtual CPUs")
	memMiB := fs.Int("mem", 256, "memory in MiB")
	network := fs.String("network", "none", "network policy (none|allow_all)")
	persist := fs.Bool("persist", false, "enable persistent volume")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *language == "" {
		return errors.New("--language is required")
	}

	createOpts := VMCreateOptions{
		Language:    *language,
		Image:       *image,
		CPUCount:    *cpu,
		MemoryMiB:   *memMiB,
		NetworkMode: *network,
		Persist:     *persist,
	}

	record, err := c.vmService.Create(ctx, createOpts)
	if err != nil {
		return err
	}

	c.logger.Info("vm created", map[string]any{
		"id":         record.ID,
		"language":   record.Language,
		"rootfs":     record.RootFSImage,
		"cpu_count":  record.CPUCount,
		"memoryMiB":  record.MemoryMiB,
		"network":    record.NetworkMode,
		"persisted":  record.Persist,
		"created_at": record.CreatedAt,
	})

	return nil
}

func (c *CLI) handleVMRun(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm run", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	vmID := fs.String("vm", "", "target VM identifier")
	cmd := fs.String("cmd", "", "command to execute inside the guest")
	file := fs.String("file", "", "optional file to stage inside /workspace/in")
	timeout := fs.Int("timeout", 0, "execution timeout in seconds (required)")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *vmID == "" {
		return errors.New("--vm is required")
	}
	if *cmd == "" {
		return errors.New("--cmd is required")
	}
	if *timeout <= 0 {
		return errors.New("--timeout must be greater than zero")
	}

	runOpts := VMRunOptions{
		VMID:    *vmID,
		Command: *cmd,
		File:    *file,
		Timeout: *timeout,
	}

	runResult, err := c.vmService.Run(ctx, runOpts)
	if err != nil {
		return err
	}

	c.logger.Info("vm run", map[string]any{
		"vm":        runOpts.VMID,
		"exit_code": runResult.ExitCode,
		"stdout":    runResult.StdoutPath,
		"stderr":    runResult.StderrPath,
		"duration":  runResult.Duration.String(),
	})

	return nil
}

func (c *CLI) handleVMStop(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm stop", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	vmID := fs.String("vm", "", "target VM identifier")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *vmID == "" {
		return errors.New("--vm is required")
	}

	if err := c.vmService.Stop(ctx, *vmID); err != nil {
		return err
	}

	c.logger.Info("vm stopped", map[string]any{"vm": *vmID})
	return nil
}

func (c *CLI) handleVMClean(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm clean", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	vmID := fs.String("vm", "", "target VM identifier")
	keepPersist := fs.Bool("keep-persist", false, "retain persistent volume")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *vmID == "" {
		return errors.New("--vm is required")
	}

	if err := c.vmService.Clean(ctx, *vmID, *keepPersist); err != nil {
		return err
	}

	c.logger.Info("vm cleaned", map[string]any{"vm": *vmID, "keep_persist": *keepPersist})
	return nil
}
