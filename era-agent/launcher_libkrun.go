//go:build libkrun

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
	libkrunBinaryName = "libkrun"
	libkrunDirName    = "libkrun"
)

func newLibkrunVMLauncher() (VMLauncher, error) {
	launcher := &libkrunVMLauncher{
		binary: libkrunBinaryName,
	}
	
	// Verify libkrun is available
	if err := launcher.verifyBinary(); err != nil {
		return nil, err
	}
	
	return launcher, nil
}

type libkrunVMLauncher struct {
	binary string
}

func (l *libkrunVMLauncher) verifyBinary() error {
	cmd := exec.Command(l.binary, "--help")
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("libkrun binary not found or not executable: %w", err)
	}
	return nil
}

func (l *libkrunVMLauncher) Launch(ctx context.Context, record VMRecord) error {
	// libkrun typically uses environment variables and direct execution
	// Set up environment and execute the rootfs image directly
	
	env := l.setupEnvironment(record)
	
	// For libkrun, we typically need to prepare the environment differently
	// This is a simplified representation - real libkrun uses different mechanisms
	cmd := exec.CommandContext(ctx, l.binary)
	
	// Set environment variables
	cmd.Env = env
	
	// For this implementation, we'll simulate a libkrun launch
	// In reality, libkrun has different parameters than krunvm
	args := []string{}
	
	// Add CPU and memory constraints
	args = append(args, "--cpus", strconv.Itoa(record.CPUCount))
	args = append(args, "--memory", strconv.Itoa(record.MemoryMiB))
	
	// Set rootfs path
	args = append(args, "--root", record.RootFSImage)  // This is a hypothetical interface
	
	// Add volume mounts if needed
	if !record.Storage.DisableGuestVolumes && strings.TrimSpace(record.Storage.Root) != "" {
		// Add volume mappings
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
	
	// Add the VM ID as a name
	args = append(args, "--name", record.ID)
	
	cmd.Args = append([]string{l.binary}, args...)
	
	return cmd.Run()
}

func (l *libkrunVMLauncher) Stop(ctx context.Context, vmID string) error {
	// In a real libkrun implementation, this would send a signal to stop the VM
	// For now, we'll simulate by using a hypothetical command
	args := []string{"stop", vmID}
	
	cmd := exec.CommandContext(ctx, l.binary, args...)
	return cmd.Run()
}

func (l *libkrunVMLauncher) Cleanup(ctx context.Context, vmID string) error {
	// Cleanup for libkrun would involve stopping and removing resources
	err := l.Stop(ctx, vmID)
	if err != nil && !errors.Is(err, errVMNotFound) {
		return err
	}
	
	// Additional cleanup if needed
	return nil
}

func (l *libkrunVMLauncher) Run(ctx context.Context, record VMRecord, opts VMRunOptions, stdout io.Writer, stderr io.Writer) (int, error) {
	// For libkrun, execute command in the running VM context
	// This is an abstraction since libkrun works differently than krunvm
	
	// Use base64 encoding to safely pass the command and avoid quote issues
	encodedCmd := base64.StdEncoding.EncodeToString([]byte(opts.Command))
	args := []string{
		"exec",  // hypothetical command for libkrun
		record.ID,
		"--",
		"/bin/bash",
		"-c",
		fmt.Sprintf("echo %s | base64 -d | bash", encodedCmd),
	}

	cmd := exec.CommandContext(ctx, l.binary, args...)
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	
	err := cmd.Run()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return exitErr.ExitCode(), &commandError{
				args:   append([]string{l.binary}, args...),
				err:    err,
				stdout: "", // We can't capture this easily
				stderr: "", // We can't capture this easily
			}
		}
		return -1, err
	}

	return 0, nil
}

func (l *libkrunVMLauncher) Shell(ctx context.Context, record VMRecord, shellCmd string, stdin io.Reader, stdout, stderr io.Writer) (int, error) {
	// Parse the shell command to split it into command and arguments
	parts := strings.Fields(shellCmd)
	if len(parts) == 0 {
		return -1, errors.New("shell command cannot be empty")
	}

	args := []string{
		"exec",  // hypothetical command for libkrun
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
				stdout: "", // We can't capture this for interactive mode easily
				stderr: "", // We can't capture this for interactive mode easily
			}
		}
		return -1, err
	}

	return 0, nil
}

func (l *libkrunVMLauncher) List(ctx context.Context) ([]string, error) {
	// List all running VMs using libkrun
	args := []string{"list"}  // hypothetical command
	
	cmd := exec.CommandContext(ctx, l.binary, args...)
	
	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf
	
	err := cmd.Run()
	if err != nil {
		return nil, fmt.Errorf("list command failed: %w", err)
	}

	// Parse the output to extract VM names
	output := stdoutBuf.String()
	scanner := bufio.NewScanner(strings.NewReader(output))
	names := make([]string, 0)
	
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" && !strings.HasPrefix(line, "#") { // Skip comments
			names = append(names, line)
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return names, nil
}

func (l *libkrunVMLauncher) setupEnvironment(record VMRecord) []string {
	// Set up environment variables for libkrun
	env := append([]string{}, os.Environ()...)
	
	// Add libkrun-specific environment variables
	env = append(env, fmt.Sprintf("LIBKRUN_DATA_DIR=%s", l.dataDir()))
	
	// Add Darwin-specific library paths (similar to krunvm)
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
	
	return env
}

func (l *libkrunVMLauncher) dataDir() string {
	root := stateRoot()
	dataDir := filepath.Join(root, libkrunDirName)
	if err := ensureDir(dataDir); err != nil {
		return filepath.Join(os.TempDir(), libkrunDirName)
	}
	return dataDir
}