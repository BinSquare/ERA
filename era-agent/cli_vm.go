package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"text/tabwriter"
	"time"
)

type stringListFlag []string

func (s *stringListFlag) String() string {
	return strings.Join(*s, ",")
}

func (s *stringListFlag) Set(value string) error {
	*s = append(*s, value)
	return nil
}

func (c *CLI) executeVM(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return errors.New("vm subcommand required")
	}

	switch args[0] {
	case "create":
		return c.handleVMCreate(ctx, args[1:])
	case "run":
		return c.handleVMRun(ctx, args[1:])
	case "exec":
		return c.handleVMExec(ctx, args[1:])
	case "shell":
		return c.handleVMShell(ctx, args[1:])
	case "temp":
		return c.handleVMTemp(ctx, args[1:])
	case "list":
		return c.handleVMList(ctx, args[1:])
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
	file := fs.String("file", "", "optional file to stage inside /in")
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
		var runErr *VMRunError
		if errors.As(err, &runErr) {
			runResult = runErr.Result
			c.logger.Error("vm run failed", map[string]any{
				"vm":        runOpts.VMID,
				"exit_code": runResult.ExitCode,
				"stdout":    runResult.StdoutPath,
				"stderr":    runResult.StderrPath,
				"duration":  runResult.Duration.String(),
				"error":     err.Error(),
			})
			return err
		}
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

func (c *CLI) handleVMExec(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm exec", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	cmd := fs.String("cmd", "", "command to execute inside the guest")
	file := fs.String("file", "", "optional file to stage inside /in")
	timeout := fs.Int("timeout", 30, "execution timeout in seconds")
	all := fs.Bool("all", false, "execute on all ready VMs")
	var vmIDs stringListFlag
	fs.Var(&vmIDs, "vm", "target VM identifier (repeatable)")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *cmd == "" {
		return errors.New("--cmd is required")
	}
	if *timeout <= 0 {
		return errors.New("--timeout must be greater than zero")
	}
	if len(vmIDs) == 0 && !*all {
		return errors.New("specify at least one --vm or use --all")
	}

	targets := make([]VMRecord, 0)
	seen := make(map[string]struct{})

	if *all {
		records, listErr := c.vmService.List(ctx)
		if listErr != nil {
			c.logger.Warn("partial vm list", map[string]any{"error": listErr.Error()})
		}
		for _, record := range records {
			if record.Status != vmStatusReady && record.Status != vmStatusRunning {
				continue
			}
			if _, exists := seen[record.ID]; exists {
				continue
			}
			targets = append(targets, record)
			seen[record.ID] = struct{}{}
		}
	}

	for _, id := range vmIDs {
		record, ok := c.vmService.Get(id)
		if !ok {
			return fmt.Errorf("vm not found: %s", id)
		}
		if record.Status != vmStatusReady && record.Status != vmStatusRunning {
			return fmt.Errorf("vm %s is not ready or running", id)
		}
		if _, exists := seen[record.ID]; exists {
			continue
		}
		targets = append(targets, record)
		seen[record.ID] = struct{}{}
	}

	if len(targets) == 0 {
		return errors.New("no matching VMs available to execute command")
	}

	var execErrors []error
	for _, target := range targets {
		command := *cmd

		runOpts := VMRunOptions{
			VMID:    target.ID,
			Command: command,
			File:    *file,
			Timeout: *timeout,
		}

		runResult, err := c.vmService.Run(ctx, runOpts)
		if err != nil {
			var runErr *VMRunError
			if errors.As(err, &runErr) {
				runResult = runErr.Result
			}
			c.logger.Error("vm exec failed", map[string]any{
				"vm":        target.ID,
				"language":  target.Language,
				"exit_code": runResult.ExitCode,
				"stdout":    runResult.StdoutPath,
				"stderr":    runResult.StderrPath,
				"duration":  runResult.Duration.String(),
				"error":     err.Error(),
			})
			execErrors = append(execErrors, fmt.Errorf("%s: %w", target.ID, err))
			continue
		}

		c.logger.Info("vm exec", map[string]any{
			"vm":        target.ID,
			"language":  target.Language,
			"exit_code": runResult.ExitCode,
			"stdout":    runResult.StdoutPath,
			"stderr":    runResult.StderrPath,
			"duration":  runResult.Duration.String(),
		})

		if err := printExecOutput(runResult.StdoutPath, runResult.StderrPath); err != nil {
			c.logger.Warn("failed to print exec output", map[string]any{
				"vm":    target.ID,
				"error": err.Error(),
			})
		}
	}

	if len(execErrors) > 0 {
		return errors.Join(execErrors...)
	}

	return nil
}

func (c *CLI) handleVMShell(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm shell", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	vmID := fs.String("vm", "", "target VM identifier")
	shellCmd := fs.String("cmd", "/bin/bash", "shell command to execute")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *vmID == "" {
		return errors.New("--vm is required")
	}

	record, ok := c.vmService.Get(*vmID)
	if !ok {
		return fmt.Errorf("vm not found: %s", *vmID)
	}

	if record.Status != vmStatusReady && record.Status != vmStatusRunning {
		return fmt.Errorf("vm %s is not ready or running", *vmID)
	}

	// For interactive shell, we need to handle stdin/stdout/stderr directly
	c.logger.Info("vm shell", map[string]any{
		"vm":       *vmID,
		"language": record.Language,
		"shell":    *shellCmd,
	})

	// Use the launcher's Shell method for interactive execution
	exitCode, err := c.vmService.launcher.Shell(ctx, record, *shellCmd, os.Stdin, os.Stdout, os.Stderr)
	if err != nil {
		c.logger.Error("vm shell failed", map[string]any{
			"vm":        *vmID,
			"exit_code": exitCode,
			"error":     err.Error(),
		})
		return fmt.Errorf("shell command exited with code %d: %w", exitCode, err)
	}

	c.logger.Info("vm shell completed", map[string]any{
		"vm":        *vmID,
		"exit_code": exitCode,
	})

	return nil
}

func (c *CLI) handleVMTemp(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm temp", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	language := fs.String("language", "python", "guest language runtime")
	image := fs.String("image", "", "override rootfs image") 
	cmd := fs.String("cmd", "", "command to execute inside the guest")
	file := fs.String("file", "", "optional file to stage inside /in")
	timeout := fs.Int("timeout", 30, "execution timeout in seconds")
	cpu := fs.Int("cpu", 1, "virtual CPUs")
	memMiB := fs.Int("mem", 256, "memory in MiB")
	network := fs.String("network", "none", "network policy (none|allow_all)")
	persist := fs.Bool("persist", false, "enable persistent volume")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if *cmd == "" {
		return errors.New("--cmd is required")
	}
	if *timeout <= 0 {
		return errors.New("--timeout must be greater than zero")
	}
	if *cpu <= 0 {
		return errors.New("--cpu must be greater than zero")
	}
	if *memMiB <= 0 {
		return errors.New("--mem must be greater than zero")
	}

	// Create temporary VM
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
		return fmt.Errorf("failed to create temporary VM: %w", err)
	}

	vmID := record.ID
	c.logger.Info("temporary vm created", map[string]any{
		"id":         vmID,
		"language":   record.Language,
		"rootfs":     record.RootFSImage,
		"cpu_count":  record.CPUCount,
		"memoryMiB":  record.MemoryMiB,
		"network":    record.NetworkMode,
		"persisted":  record.Persist,
	})

	// Run the command in the temporary VM
	runOpts := VMRunOptions{
		VMID:    vmID,
		Command: *cmd,
		File:    *file,
		Timeout: *timeout,
	}

	runResult, err := c.vmService.Run(ctx, runOpts)
	if err != nil {
		var runErr *VMRunError
		if errors.As(err, &runErr) {
			runResult = runErr.Result
		}
		c.logger.Error("temporary vm execution failed", map[string]any{
			"vm":        vmID,
			"language":  record.Language,
			"exit_code": runResult.ExitCode,
			"stdout":    runResult.StdoutPath,
			"stderr":    runResult.StderrPath,
			"duration":  runResult.Duration.String(),
			"error":     err.Error(),
		})
		// Still attempt cleanup even if execution failed
		if cleanupErr := c.vmService.Clean(ctx, vmID, false); cleanupErr != nil {
			c.logger.Error("failed to cleanup temporary vm after execution failure", map[string]any{
				"vm":    vmID,
				"error": cleanupErr.Error(),
			})
		}
		return err
	}

	c.logger.Info("temporary vm execution completed", map[string]any{
		"vm":        vmID,
		"language":  record.Language,
		"exit_code": runResult.ExitCode,
		"stdout":    runResult.StdoutPath,
		"stderr":    runResult.StderrPath,
		"duration":  runResult.Duration.String(),
	})

	// Print execution output
	if err := printExecOutput(runResult.StdoutPath, runResult.StderrPath); err != nil {
		c.logger.Warn("failed to print exec output", map[string]any{
			"vm":    vmID,
			"error": err.Error(),
		})
	}

	// Clean up the temporary VM
	if err := c.vmService.Clean(ctx, vmID, false); err != nil {
		c.logger.Error("failed to cleanup temporary vm", map[string]any{
			"vm":    vmID,
			"error": err.Error(),
		})
		return fmt.Errorf("temporary vm execution succeeded but cleanup failed: %w", err)
	}

	c.logger.Info("temporary vm cleaned up", map[string]any{
		"vm": vmID,
	})

	return nil
}

func (c *CLI) handleVMList(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm list", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	statusFilter := fs.String("status", "", "filter by VM status")
	includeAll := fs.Bool("all", false, "include stopped VMs")

	if err := fs.Parse(args); err != nil {
		return err
	}

	records, listErr := c.vmService.List(ctx)
	if listErr != nil {
		c.logger.Warn("partial vm list", map[string]any{"error": listErr.Error()})
	}

	filter := strings.ToLower(strings.TrimSpace(*statusFilter))
	showStoppedByDefault := filter != ""
	rows := make([]VMRecord, 0)

	for _, record := range records {
		if !*includeAll && !showStoppedByDefault && record.Status == vmStatusStopped {
			continue
		}
		if filter != "" && strings.ToLower(record.Status) != filter {
			continue
		}
		rows = append(rows, record)
	}

	if len(rows) == 0 {
		fmt.Println("No VMs found.")
		if filter != "" {
			fmt.Printf("Status filter: %s\n", filter)
		}
		if !*includeAll && filter == "" {
			fmt.Println("(use --all to include stopped VMs)")
		}
		return nil
	}

	renderVMTable(rows)

	fmt.Printf("\nTotal: %d", len(rows))
	if filter != "" {
		fmt.Printf(" (status=%s)", filter)
	}
	if !*includeAll && filter == "" {
		fmt.Print(" (use --all to include stopped VMs)")
	}
	fmt.Println()

	return nil
}

func (c *CLI) handleVMStop(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm stop", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	all := fs.Bool("all", false, "stop all VMs")
	var vmIDs stringListFlag
	fs.Var(&vmIDs, "vm", "target VM identifier (repeatable)")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if len(vmIDs) == 0 && !*all {
		return errors.New("specify at least one --vm or use --all")
	}

	targets := make([]VMRecord, 0)
	seen := make(map[string]struct{})
	var opErrors []error

	if *all {
		records, listErr := c.vmService.List(ctx)
		if listErr != nil {
			c.logger.Warn("partial vm list", map[string]any{"error": listErr.Error()})
		}
		for _, record := range records {
			if _, exists := seen[record.ID]; exists {
				continue
			}
			targets = append(targets, record)
			seen[record.ID] = struct{}{}
		}
	}

	for _, id := range vmIDs {
		record, ok := c.vmService.Get(id)
		if !ok {
			err := fmt.Errorf("vm not found: %s", id)
			c.logger.Error("vm stop failed", map[string]any{"vm": id, "error": err.Error()})
			opErrors = append(opErrors, err)
			continue
		}
		if _, exists := seen[record.ID]; exists {
			continue
		}
		targets = append(targets, record)
		seen[record.ID] = struct{}{}
	}

	if len(targets) == 0 {
		if len(opErrors) > 0 {
			return errors.Join(opErrors...)
		}
		return errors.New("no matching VMs to stop")
	}

	for _, record := range targets {
		if err := c.vmService.Stop(ctx, record.ID); err != nil {
			c.logger.Error("vm stop failed", map[string]any{
				"vm":     record.ID,
				"error":  err.Error(),
				"status": record.Status,
			})
			opErrors = append(opErrors, fmt.Errorf("%s: %w", record.ID, err))
			continue
		}

		c.logger.Info("vm stopped", map[string]any{
			"vm":       record.ID,
			"language": record.Language,
		})
	}

	if len(opErrors) > 0 {
		return errors.Join(opErrors...)
	}

	return nil
}

func (c *CLI) handleVMClean(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent vm clean", flag.ContinueOnError)
	fs.SetOutput(io.Discard)

	all := fs.Bool("all", false, "delete all VMs")
	var vmIDs stringListFlag
	fs.Var(&vmIDs, "vm", "target VM identifier (repeatable)")
	keepPersist := fs.Bool("keep-persist", false, "retain persistent volume")

	if err := fs.Parse(args); err != nil {
		return err
	}

	if len(vmIDs) == 0 && !*all {
		return errors.New("specify at least one --vm or use --all")
	}

	targets := make([]VMRecord, 0)
	seen := make(map[string]struct{})
	var opErrors []error

	if *all {
		records, listErr := c.vmService.List(ctx)
		if listErr != nil {
			c.logger.Warn("partial vm list", map[string]any{"error": listErr.Error()})
		}
		for _, record := range records {
			if _, exists := seen[record.ID]; exists {
				continue
			}
			targets = append(targets, record)
			seen[record.ID] = struct{}{}
		}
	}

	for _, id := range vmIDs {
		record, ok := c.vmService.Get(id)
		if !ok {
			err := fmt.Errorf("vm not found: %s", id)
			c.logger.Error("vm clean failed", map[string]any{"vm": id, "error": err.Error()})
			opErrors = append(opErrors, err)
			continue
		}
		if _, exists := seen[record.ID]; exists {
			continue
		}
		targets = append(targets, record)
		seen[record.ID] = struct{}{}
	}

	if len(targets) == 0 {
		if len(opErrors) > 0 {
			return errors.Join(opErrors...)
		}
		return errors.New("no matching VMs to clean")
	}

	for _, record := range targets {
		if err := c.vmService.Clean(ctx, record.ID, *keepPersist); err != nil {
			c.logger.Error("vm clean failed", map[string]any{
				"vm":     record.ID,
				"error":  err.Error(),
				"status": record.Status,
			})
			opErrors = append(opErrors, fmt.Errorf("%s: %w", record.ID, err))
			continue
		}

		c.logger.Info("vm cleaned", map[string]any{
			"vm":           record.ID,
			"language":     record.Language,
			"keep_persist": *keepPersist,
		})
	}

	if len(opErrors) > 0 {
		return errors.Join(opErrors...)
	}

	return nil
}

func renderVMTable(records []VMRecord) {
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "ID\tLanguage\tStatus\tCPU\tMem(MiB)\tPersist\tCreated\tLast Run")
	for _, record := range records {
		persist := "no"
		if record.Persist {
			persist = "yes"
		}
		fmt.Fprintf(
			w,
			"%s\t%s\t%s\t%d\t%d\t%s\t%s\t%s\n",
			record.ID,
			record.Language,
			strings.ToLower(record.Status),
			record.CPUCount,
			record.MemoryMiB,
			persist,
			formatTimestamp(record.CreatedAt),
			formatTimestamp(record.LastRunAt),
		)
	}
	_ = w.Flush()
}

func formatTimestamp(ts time.Time) string {
	if ts.IsZero() {
		return "-"
	}
	return ts.Local().Format("2006-01-02 15:04:05")
}

func printExecOutput(stdoutPath, stderrPath string) error {
	if err := streamFile(stdoutPath, os.Stdout); err != nil {
		return err
	}
	if err := streamFile(stderrPath, os.Stderr); err != nil {
		return err
	}
	return nil
}

func streamFile(path string, dest *os.File) error {
	cleaned := strings.TrimSpace(path)
	if cleaned == "" {
		return nil
	}
	data, err := os.ReadFile(cleaned)
	if err != nil {
		return err
	}
	if len(data) == 0 {
		return nil
	}
	if _, err := dest.Write(data); err != nil {
		return err
	}
	if len(data) == 0 || data[len(data)-1] == '\n' {
		return nil
	}
	_, err = dest.WriteString("\n")
	return err
}
