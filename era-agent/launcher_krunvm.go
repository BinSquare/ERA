package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

const (
	krunvmBinaryName         = "krunvm"
	krunvmDirName            = "krunvm"
	containersDirName        = "containers"
	containerStorageConfName = "storage.conf"

	guestInputPath   = "/in"
	guestOutputPath  = "/out"
	guestPersistPath = "/persist"
)

func newKrunVMLauncher() VMLauncher {
	return &krunVMLauncher{
		binary: krunvmBinaryName,
	}
}

type krunVMLauncher struct {
	binary string
}

func (l *krunVMLauncher) Launch(ctx context.Context, record VMRecord) error {
	// Validate macOS-specific requirements
	if err := validateMacOSKrunvmSetup(); err != nil {
		return fmt.Errorf("macOS setup validation failed: %w", err)
	}

	args := []string{
		"create",
		"--name", record.ID,
		"--cpus", strconv.Itoa(record.CPUCount),
		"--mem", strconv.Itoa(record.MemoryMiB),
	}

	if !record.Storage.DisableGuestVolumes && strings.TrimSpace(record.Storage.Root) != "" {
		volumes := []string{
			formatVolume(record.Storage.InputPath, guestInputPath),
			formatVolume(record.Storage.OutputPath, guestOutputPath),
		}
		if record.Storage.PersistPath != "" {
			volumes = append(volumes, formatVolume(record.Storage.PersistPath, guestPersistPath))
		}

		for _, volume := range volumes {
			if volume == "" {
				continue
			}
			args = append(args, "--volume", volume)
		}
	}

	args = append(args, record.RootFSImage)

	return l.runCommand(ctx, args, nil, nil)
}

func (l *krunVMLauncher) Stop(ctx context.Context, vmID string) error {
	return l.deleteVM(ctx, vmID)
}

func (l *krunVMLauncher) Cleanup(ctx context.Context, vmID string) error {
	if err := l.deleteVM(ctx, vmID); err != nil && !errors.Is(err, errVMNotFound) {
		return err
	}
	return nil
}

func (l *krunVMLauncher) Run(ctx context.Context, record VMRecord, opts VMRunOptions, stdout io.Writer, stderr io.Writer) (int, error) {
	// Use base64 encoding to safely pass the command and avoid quote issues
	encodedCmd := base64.StdEncoding.EncodeToString([]byte(opts.Command))
	args := []string{
		"start",
		record.ID,
		"--",
		"/bin/bash",
		"-c",
		fmt.Sprintf("echo %s | base64 -d | bash", encodedCmd),
	}

	exitCode, _, _, err := l.runCommandWithOutput(ctx, args, stdout, stderr)
	return exitCode, err
}
func (l *krunVMLauncher) List(ctx context.Context) ([]string, error) {
	args := []string{"list"}
	_, stdout, _, err := l.runCommandWithOutput(ctx, args, nil, nil)
	if err != nil {
		return nil, err
	}

	scanner := bufio.NewScanner(strings.NewReader(stdout))
	names := make([]string, 0)
	expectName := true

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			expectName = true
			continue
		}
		if expectName {
			names = append(names, line)
			expectName = false
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return names, nil
}

func (l *krunVMLauncher) Shell(ctx context.Context, record VMRecord, shellCmd string, stdin io.Reader, stdout, stderr io.Writer) (int, error) {
	// Parse the shell command to split it into command and arguments
	parts := strings.Fields(shellCmd)
	if len(parts) == 0 {
		return -1, errors.New("shell command cannot be empty")
	}

	args := []string{
		"start",
		record.ID,
		"--",
	}
	args = append(args, parts...) // This will expand to command + all its arguments

	cmd := exec.CommandContext(ctx, l.binary, args...)
	cmd.Stdin = stdin
	cmd.Stdout = stdout
	cmd.Stderr = stderr

	err := cmd.Run()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return exitErr.ExitCode(), &commandError{
				args:   append([]string{l.binary}, args...),
				err:    err,
				stdout: "",  // We can't capture this for interactive mode easily
				stderr: "",  // We can't capture this for interactive mode easily
			}
		}
		return -1, err
	}

	return 0, nil
}

func (l *krunVMLauncher) deleteVM(ctx context.Context, vmID string) error {
	if strings.TrimSpace(vmID) == "" {
		return errVMNotFound
	}
	args := []string{"delete", vmID}
	err := l.runCommand(ctx, args, nil, nil)
	if err == nil {
		return nil
	}

	if errors.Is(err, errVMNotFound) {
		return err
	}

	var cmdErr *commandError
	if errors.As(err, &cmdErr) {
		lowerStdout := strings.ToLower(cmdErr.stdout)
		lowerStderr := strings.ToLower(cmdErr.stderr)
		if strings.Contains(lowerStdout, "no vm found") ||
			strings.Contains(lowerStderr, "not found") ||
			strings.Contains(lowerStderr, "no such file") {
			return errVMNotFound
		}
	}
	return err
}

func (l *krunVMLauncher) runCommand(ctx context.Context, args []string, stdout io.Writer, stderr io.Writer) error {
	_, _, _, err := l.runCommandWithOutput(ctx, args, stdout, stderr)
	return err
}

func (l *krunVMLauncher) runCommandWithOutput(ctx context.Context, args []string, stdout io.Writer, stderr io.Writer) (int, string, string, error) {
	if len(args) == 0 {
		return -1, "", "", errors.New("krunvm command missing")
	}

	env := append([]string{}, os.Environ()...)
	env = append(env, fmt.Sprintf("KRUNVM_DATA_DIR=%s", l.dataDir()))

	if runtime.GOOS == "darwin" {
		libPaths := []string{}
		if _, err := os.Stat("/opt/homebrew/lib"); err == nil {
			libPaths = append(libPaths, "/opt/homebrew/lib")
		}
		if _, err := os.Stat("/usr/local/lib"); err == nil {
			libPaths = append(libPaths, "/usr/local/lib")
		}

		if len(libPaths) > 0 {
			dyldPath := os.Getenv("DYLD_LIBRARY_PATH")
			if dyldPath != "" {
				dyldPath = strings.Join(libPaths, ":") + ":" + dyldPath
			} else {
				dyldPath = strings.Join(libPaths, ":")
			}
			env = append(env, "DYLD_LIBRARY_PATH="+dyldPath)
		}
	}

	if cfg := ensureContainersConfig(); cfg.valid() {
		if cfg.storageConf != "" {
			env = append(env,
				fmt.Sprintf("CONTAINERS_STORAGE_CONF=%s", cfg.storageConf),
				fmt.Sprintf("CONTAINERS_STORAGE_CONFIG=%s", cfg.storageConf),
				fmt.Sprintf("STORAGE_CONF=%s", cfg.storageConf),
				fmt.Sprintf("BUILDAH_STORAGE_CONF=%s", cfg.storageConf),
			)
		}
		if cfg.policyJSON != "" {
			env = append(env,
				fmt.Sprintf("CONTAINERS_POLICY=%s", cfg.policyJSON),
				fmt.Sprintf("SIGNATURE_POLICY=%s", cfg.policyJSON),
				fmt.Sprintf("BUILDAH_SIGNATURE_POLICY=%s", cfg.policyJSON),
			)
		}
		if cfg.registriesConf != "" {
			env = append(env,
				fmt.Sprintf("CONTAINERS_REGISTRIES_CONF=%s", cfg.registriesConf),
				fmt.Sprintf("REGISTRIES_CONFIG_PATH=%s", cfg.registriesConf),
				fmt.Sprintf("BUILDAH_REGISTRIES_CONF=%s", cfg.registriesConf),
			)
		}
		if cfg.configRoot != "" {
			env = append(env, fmt.Sprintf("XDG_CONFIG_HOME=%s", cfg.configRoot))
		}
	}

	cmd := exec.CommandContext(ctx, l.binary, args...)
	cmd.Env = env

	var stdoutBuf, stderrBuf bytes.Buffer
	if stdout != nil {
		cmd.Stdout = stdout
	} else {
		cmd.Stdout = &stdoutBuf
	}
	if stderr != nil {
		cmd.Stderr = stderr
	} else {
		cmd.Stderr = &stderrBuf
	}

	err := cmd.Run()
	exitCode := 0
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			exitCode = exitErr.ExitCode()
		} else {
			return -1, "", "", err
		}
	}

	if exitCode != 0 {
		return exitCode, stdoutBuf.String(), stderrBuf.String(), &commandError{
			args:   append([]string{l.binary}, args...),
			err:    err,
			stdout: stdoutBuf.String(),
			stderr: stderrBuf.String(),
		}
	}

	stdoutStr := ""
	stderrStr := ""
	if stdout == nil {
		stdoutStr = stdoutBuf.String()
	}
	if stderr == nil {
		stderrStr = stderrBuf.String()
	}

	return exitCode, stdoutStr, stderrStr, nil
}

func (l *krunVMLauncher) dataDir() string {
	root := stateRoot()
	dataDir := filepath.Join(root, krunvmDirName)
	if err := ensureDir(dataDir); err != nil {
		return filepath.Join(os.TempDir(), krunvmDirName)
	}
	return dataDir
}

type containersConfig struct {
	root           string
	storageConf    string
	policyJSON     string
	registriesConf string
	storageRoot    string
	runRoot        string
	configRoot     string
}

func (c containersConfig) valid() bool {
	return c.root != ""
}

func ensureContainersConfig() containersConfig {
	root := stateRoot()
	containersRoot := filepath.Join(root, containersDirName)
	storageRoot := filepath.Join(containersRoot, "storage")
	runRoot := filepath.Join(containersRoot, "runroot")
	policyJSON := filepath.Join(containersRoot, "policy.json")
	registriesConf := filepath.Join(containersRoot, "registries.conf")
	configRoot := root

	for _, dir := range []string{containersRoot, storageRoot, runRoot} {
		if err := ensureDir(dir); err != nil {
			return containersConfig{}
		}
	}

	confPath := filepath.Join(containersRoot, containerStorageConfName)
	confContents := fmt.Sprintf(`[storage]
driver = "vfs"
graphroot = %q
runroot = %q
rootless_storage_path = %q
`, storageRoot, runRoot, storageRoot)

	if err := os.WriteFile(confPath, []byte(confContents), 0o640); err != nil {
		return containersConfig{}
	}

	policy := `{
  "default": [
    {
      "type": "insecureAcceptAnything"
    }
  ],
  "transports": {
    "docker": {
      "": [
        {
          "type": "insecureAcceptAnything"
        }
      ]
    }
  }
}
`

	if err := os.WriteFile(policyJSON, []byte(policy), 0o640); err != nil {
		return containersConfig{}
	}

	registries := `unqualified-search-registries = ["localhost", "docker.io"]

[[registry]]
prefix = "docker.io"
location = "registry-1.docker.io"
blocked = false
insecure = false
`

	if err := os.WriteFile(registriesConf, []byte(registries), 0o640); err != nil {
		return containersConfig{}
	}

	return containersConfig{
		root:           containersRoot,
		storageConf:    confPath,
		policyJSON:     policyJSON,
		registriesConf: registriesConf,
		storageRoot:    storageRoot,
		runRoot:        runRoot,
		configRoot:     configRoot,
	}
}

type commandError struct {
	args   []string
	err    error
	stdout string
	stderr string
}

func (e *commandError) Error() string {
	var builder strings.Builder
	builder.WriteString("krunvm command failed: ")
	builder.WriteString(strings.Join(e.args, " "))

	if e.err != nil {
		builder.WriteString(": ")
		builder.WriteString(e.err.Error())
	}

	stderr := strings.TrimSpace(e.stderr)
	if stderr != "" {
		builder.WriteString(" (stderr: ")
		builder.WriteString(stderr)
		builder.WriteString(")")

		// Detect common macOS issues
		if runtime.GOOS == "darwin" {
			if strings.Contains(stderr, "mkdir /Volumes/krunvm") ||
				strings.Contains(stderr, "permission denied") {
				builder.WriteString("\n\nHINT: krunvm requires /Volumes/krunvm (case-sensitive APFS).")
				builder.WriteString("\nRun: ./scripts/macos/setup.sh")
			}
			if strings.Contains(stderr, "Error setting VM mapped volumes") {
				builder.WriteString("\n\nHINT: Ensure AGENT_ENABLE_GUEST_VOLUMES=1 is set.")
				builder.WriteString("\nRun: source ~/agentVM/.env")
			}
		}
	}

	return builder.String()
}

func (e *commandError) Unwrap() error {
	return e.err
}

func formatVolume(hostPath, guestPath string) string {
	host := strings.TrimSpace(hostPath)
	if host == "" || guestPath == "" {
		return ""
	}
	return fmt.Sprintf("%s:%s", host, guestPath)
}
