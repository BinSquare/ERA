package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

type GlobalOptions struct {
	LogLevel  string
	LogFile   string
	VMRuntime string
}

type CLI struct {
	logger    *Logger
	vmService *VMService
}

func NewCLI(logger *Logger, vmService *VMService) *CLI {
	return &CLI{
		logger:    logger,
		vmService: vmService,
	}
}

func parseGlobalOptions(args []string) (GlobalOptions, []string, error) {
	opts := GlobalOptions{
		LogLevel:  strings.ToLower(strings.TrimSpace(getenvOrDefault("AGENT_LOG_LEVEL", ""))),
		LogFile:   strings.TrimSpace(getenvOrDefault("AGENT_LOG_FILE", "")),
		VMRuntime: strings.ToLower(strings.TrimSpace(getenvOrDefault("AGENT_VM_RUNTIME", ""))),
	}
	remaining := make([]string, 0, len(args))

	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "--log-level":
			if i+1 >= len(args) {
				return opts, nil, errors.New("missing value for --log-level")
			}
			opts.LogLevel = strings.ToLower(args[i+1])
			i++
		case strings.HasPrefix(arg, "--log-level="):
			opts.LogLevel = strings.ToLower(strings.TrimPrefix(arg, "--log-level="))
		case arg == "--log-file":
			if i+1 >= len(args) {
				return opts, nil, errors.New("missing value for --log-file")
			}
			opts.LogFile = strings.TrimSpace(args[i+1])
			i++
		case strings.HasPrefix(arg, "--log-file="):
			opts.LogFile = strings.TrimSpace(strings.TrimPrefix(arg, "--log-file="))
		case arg == "--vm-runtime":
			if i+1 >= len(args) {
				return opts, nil, errors.New("missing value for --vm-runtime")
			}
			opts.VMRuntime = strings.ToLower(strings.TrimSpace(args[i+1]))
			i++
		case strings.HasPrefix(arg, "--vm-runtime="):
			opts.VMRuntime = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(arg, "--vm-runtime=")))
		default:
			remaining = append(remaining, arg)
		}
	}

	if opts.LogLevel == "" {
		opts.LogLevel = "info"
	}

	return opts, remaining, nil
}

func (c *CLI) Execute(ctx context.Context, args []string) error {
	if len(args) == 0 {
		c.printUsage()
		return nil
	}

	switch args[0] {
	case "vm":
		return c.executeVM(ctx, args[1:])
	case "-h", "--help", "help":
		c.printUsage()
		return nil
	default:
		return fmt.Errorf("unknown command: %s", args[0])
	}
}

func (c *CLI) printUsage() {
	usage := strings.Join([]string{
		"Agent CLI",
		"",
		"Usage:",
		"  agent vm create --language <python|javascript|node|ruby|golang> [--image <override>] --cpu <n> --mem <MiB> --network <none|allow_all> [--persist]",
		`  agent vm run    --vm <id> --cmd "python main.py" [--file ./main.py] --timeout <seconds>`,
		`  agent vm exec   --cmd "echo hello" [--file ./script.py] [--vm <id> ... | --all] [--timeout <seconds>]`,
		"  agent vm shell  --vm <id> [--cmd /bin/bash]",
		"  agent vm temp   --language <python> --cmd \"python -c 'print(1) '\" [--timeout <seconds>] --cpu <n> --mem <MiB>",
		"  agent vm list   [--status <state>] [--all]",
		"  agent vm stop   [--vm <id> ... | --all]",
		"  agent vm clean  [--vm <id> ... | --all] [--keep-persist]",
		"",
		"Set AGENT_LOG_LEVEL=debug for verbose logs, and use --log-file or AGENT_LOG_FILE=/path to mirror output to disk. Override AGENT_STATE_DIR to change where VM state is stored.",
		"Set AGENT_ENABLE_GUEST_VOLUMES=1 to mount /in and /out into the guest (required for --file).",
		"Select a virtualization backend with --vm-runtime=<krunvm|libkrun> or AGENT_VM_RUNTIME (defaults to krunvm).",
	}, "\n")

	fmt.Println(usage)
}
