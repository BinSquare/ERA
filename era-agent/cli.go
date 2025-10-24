package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

type GlobalOptions struct {
	LogLevel string
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
	opts := GlobalOptions{LogLevel: strings.ToLower(strings.TrimSpace(getenvOrDefault("AGENT_LOG_LEVEL", "")))}
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
	case "mcp":
		return runMCPServer(ctx, c.vmService, c.logger)
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
		"  agent serve                                                                          # Start HTTP server (or set AGENT_MODE=http)",
		"  agent mcp                                                                            # Start MCP server for Claude Desktop",
		"  agent vm create --language <python|node> [--image <override>] --cpu <n> --mem <MiB> --network <none|allow_all> [--persist]",
		`  agent vm run    --vm <id> --cmd "python main.py" [--file ./main.py] --timeout <seconds>`,
		"  agent vm stop   --vm <id>",
		"  agent vm clean  --vm <id> [--keep-persist]",
		"",
		"Environment Variables:",
		"  AGENT_MODE=http     - Run as HTTP server instead of CLI",
		"  PORT=8787           - HTTP server port (default: 8787)",
		"  AGENT_LOG_LEVEL     - Log level: debug, info, warn, error (default: info)",
		"  AGENT_STATE_DIR     - Override state directory location",
	}, "\n")

	fmt.Println(usage)
}
