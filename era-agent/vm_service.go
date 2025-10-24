package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	defaultSystemStateRoot = "/var/lib/agent"
	stateDirName           = "agent"
	stateDBFileName        = "agent.db"
	defaultGuestUIDGID     = 65532
)

var (
	errVMNotFound      = errors.New("vm not found")
	errUnsupportedLang = errors.New("unsupported language")

	stateRootOnce     sync.Once
	resolvedStateRoot string
)

type VMCreateOptions struct {
	Language    string
	Image       string
	CPUCount    int
	MemoryMiB   int
	NetworkMode string
	Persist     bool
}

type VMRunOptions struct {
	VMID    string
	Command string
	File    string
	Timeout int
}

type VMRunResult struct {
	ExitCode   int
	StdoutPath string
	StderrPath string
	Duration   time.Duration
}

type StorageLayout struct {
	Root         string
	InputPath    string
	OutputPath   string
	PersistPath  string
	StateDBPath  string
	GuestUID     int
	GuestGID     int
	NetworkMode  string
	ReadOnlyRoot bool
}

type VMRecord struct {
	ID          string
	Language    string
	RootFSImage string
	CPUCount    int
	MemoryMiB   int
	NetworkMode string
	Persist     bool
	Status      string
	Storage     StorageLayout
	CreatedAt   time.Time
	LastRunAt   time.Time
}

type VMService struct {
	logger   *Logger
	launcher VMLauncher
	store    *BoltVMStore

	mu    sync.RWMutex
	cache map[string]VMRecord
}

func NewVMService(logger *Logger) (*VMService, error) {
	store, err := NewBoltVMStore(stateRoot())
	if err != nil {
		return nil, err
	}

	records, err := store.LoadAll()
	if err != nil {
		_ = store.Close()
		return nil, err
	}

	cache := make(map[string]VMRecord, len(records))
	for _, record := range records {
		cache[record.ID] = record
		_ = ensureStorageLayout(record.Storage)
	}

	return &VMService{
		logger:   logger,
		launcher: newVMLauncher(),
		store:    store,
		cache:    cache,
	}, nil
}

func (s *VMService) Close() error {
	return s.store.Close()
}

func (s *VMService) Create(ctx context.Context, opts VMCreateOptions) (VMRecord, error) {
	language := normalizeLanguage(opts.Language)
	if language == "" {
		return VMRecord{}, errors.New("language is required")
	}

	if opts.CPUCount <= 0 {
		return VMRecord{}, errors.New("cpu must be greater than zero")
	}
	if opts.MemoryMiB <= 0 {
		return VMRecord{}, errors.New("mem must be greater than zero")
	}

	rootfs, err := s.resolveRootFS(language, opts.Image)
	if err != nil {
		return VMRecord{}, err
	}

	vmID := sanitizeID(fmt.Sprintf("%s-%d", language, time.Now().UTC().UnixNano()))
	layout, err := prepareStorage(vmID, opts.Persist)
	if err != nil {
		return VMRecord{}, err
	}
	layout.NetworkMode = opts.NetworkMode
	layout.ReadOnlyRoot = true

	record := VMRecord{
		ID:          vmID,
		Language:    language,
		RootFSImage: rootfs,
		CPUCount:    opts.CPUCount,
		MemoryMiB:   opts.MemoryMiB,
		NetworkMode: opts.NetworkMode,
		Persist:     opts.Persist,
		Status:      "provisioning",
		Storage:     layout,
		CreatedAt:   time.Now().UTC(),
	}

	if err := s.launcher.Launch(ctx, record); err != nil {
		_ = os.RemoveAll(layout.Root)
		if opts.Persist && layout.PersistPath != "" {
			_ = os.RemoveAll(layout.PersistPath)
		}
		return VMRecord{}, err
	}

	record.Status = "running"

	if err := s.store.Save(record); err != nil {
		_ = s.launcher.Cleanup(ctx, vmID)
		_ = os.RemoveAll(layout.Root)
		if opts.Persist && layout.PersistPath != "" {
			_ = os.RemoveAll(layout.PersistPath)
		}
		return VMRecord{}, err
	}

	s.mu.Lock()
	s.cache[vmID] = record
	s.mu.Unlock()

	return record, nil
}

func (s *VMService) Run(ctx context.Context, opts VMRunOptions) (VMRunResult, error) {
	if opts.Timeout <= 0 {
		return VMRunResult{}, errors.New("timeout must be positive")
	}
	if opts.Command == "" {
		return VMRunResult{}, errors.New("cmd is required")
	}

	record, err := s.fetchRecord(opts.VMID)
	if err != nil {
		return VMRunResult{}, err
	}

	if record.Status != "running" {
		return VMRunResult{}, errors.New("vm is not running")
	}

	if opts.File != "" {
		if err := stageInputFile(opts.File, record.Storage.InputPath); err != nil {
			return VMRunResult{}, err
		}
	}

	start := time.Now()

	stdoutPath := filepath.Join(record.Storage.OutputPath, "stdout.log")
	stderrPath := filepath.Join(record.Storage.OutputPath, "stderr.log")

	// Determine working directory for code execution
	// Use PersistPath for persistent VMs, otherwise use Root
	workDir := record.Storage.Root
	if record.Persist && record.Storage.PersistPath != "" {
		workDir = record.Storage.PersistPath
	}

	// Execute the command
	result, err := s.executeCommand(ctx, opts.Command, opts.Timeout, stdoutPath, stderrPath, workDir)
	if err != nil {
		return VMRunResult{}, err
	}

	result.Duration = time.Since(start)

	record.LastRunAt = time.Now().UTC()

	if err := s.store.Save(record); err != nil {
		return VMRunResult{}, err
	}

	s.mu.Lock()
	s.cache[record.ID] = record
	s.mu.Unlock()

	return result, nil
}

func (s *VMService) executeCommand(ctx context.Context, command string, timeoutSecs int, stdoutPath, stderrPath, workDir string) (VMRunResult, error) {
	// Create a context with timeout
	execCtx, cancel := context.WithTimeout(ctx, time.Duration(timeoutSecs)*time.Second)
	defer cancel()

	// Parse the command - split by spaces but respect quotes
	args := parseCommandLine(command)
	if len(args) == 0 {
		return VMRunResult{}, errors.New("empty command")
	}

	// Create the command
	cmd := exec.CommandContext(execCtx, args[0], args[1:]...)

	// Set working directory for command execution
	cmd.Dir = workDir

	// Capture stdout and stderr
	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	// Execute the command
	err := cmd.Run()

	// Get exit code
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else if execCtx.Err() == context.DeadlineExceeded {
			exitCode = 124 // Timeout exit code
		} else {
			exitCode = 1
		}
	}

	// Write outputs to files
	if err := os.WriteFile(stdoutPath, stdoutBuf.Bytes(), 0o640); err != nil {
		return VMRunResult{}, fmt.Errorf("failed to write stdout: %w", err)
	}
	if err := os.WriteFile(stderrPath, stderrBuf.Bytes(), 0o640); err != nil {
		return VMRunResult{}, fmt.Errorf("failed to write stderr: %w", err)
	}

	return VMRunResult{
		ExitCode:   exitCode,
		StdoutPath: stdoutPath,
		StderrPath: stderrPath,
	}, nil
}

func parseCommandLine(command string) []string {
	var args []string
	var current strings.Builder
	inQuote := false
	escapeNext := false

	for i, r := range command {
		if escapeNext {
			current.WriteRune(r)
			escapeNext = false
			continue
		}

		switch r {
		case '\\':
			if i+1 < len(command) {
				escapeNext = true
			} else {
				current.WriteRune(r)
			}
		case '"':
			inQuote = !inQuote
		case ' ', '\t', '\n':
			if inQuote {
				current.WriteRune(r)
			} else if current.Len() > 0 {
				args = append(args, current.String())
				current.Reset()
			}
		default:
			current.WriteRune(r)
		}
	}

	if current.Len() > 0 {
		args = append(args, current.String())
	}

	return args
}

func (s *VMService) Stop(ctx context.Context, vmID string) error {
	record, err := s.fetchRecord(vmID)
	if err != nil {
		return err
	}

	if err := s.launcher.Stop(ctx, vmID); err != nil {
		return err
	}

	record.Status = "stopped"
	record.LastRunAt = time.Now().UTC()

	if err := s.store.Save(record); err != nil {
		return err
	}

	s.mu.Lock()
	s.cache[vmID] = record
	s.mu.Unlock()

	return nil
}

func (s *VMService) Clean(ctx context.Context, vmID string, keepPersist bool) error {
	record, err := s.fetchRecord(vmID)
	if err != nil {
		return err
	}

	if err := s.launcher.Cleanup(ctx, vmID); err != nil {
		return err
	}

	if err := os.RemoveAll(record.Storage.Root); err != nil && !os.IsNotExist(err) {
		return err
	}
	if !keepPersist && record.Storage.PersistPath != "" {
		if err := os.RemoveAll(record.Storage.PersistPath); err != nil && !os.IsNotExist(err) {
			return err
		}
	}

	if err := s.store.Delete(vmID); err != nil {
		return err
	}

	s.mu.Lock()
	delete(s.cache, vmID)
	s.mu.Unlock()

	return nil
}

func (s *VMService) Get(vmID string) (VMRecord, bool) {
	record, err := s.fetchRecord(vmID)
	if err != nil {
		return VMRecord{}, false
	}
	return record, true
}

func (s *VMService) GetVMWorkDir(vmID string) string {
	// Get the VM record to determine the correct work directory
	record, err := s.fetchRecord(vmID)
	if err != nil {
		// Fallback to default if record not found
		return filepath.Join(stateRoot(), "vms", vmID)
	}

	// For persistent VMs, return the persist path where files are stored
	// For ephemeral VMs, return the root directory
	if record.Persist && record.Storage.PersistPath != "" {
		return record.Storage.PersistPath
	}
	return record.Storage.Root
}

func (s *VMService) List() []VMRecord {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := make([]VMRecord, 0, len(s.cache))
	for _, record := range s.cache {
		records = append(records, record)
	}
	return records
}

func (s *VMService) fetchRecord(vmID string) (VMRecord, error) {
	if strings.TrimSpace(vmID) == "" {
		return VMRecord{}, errVMNotFound
	}

	s.mu.RLock()
	record, ok := s.cache[vmID]
	s.mu.RUnlock()
	if ok {
		return record, nil
	}

	record, err := s.store.Get(vmID)
	if err != nil {
		if errors.Is(err, errNotFound) {
			return VMRecord{}, errVMNotFound
		}
		return VMRecord{}, err
	}

	s.mu.Lock()
	s.cache[vmID] = record
	s.mu.Unlock()

	return record, nil
}

func (s *VMService) resolveRootFS(language, override string) (string, error) {
	if override != "" {
		return override, nil
	}

	dateSuffix := time.Now().UTC().Format("20060102")

	switch language {
	case "python":
		return fmt.Sprintf("agent/python:3.11-%s", dateSuffix), nil
	case "node":
		return fmt.Sprintf("agent/node:20-%s", dateSuffix), nil
	case "go", "golang":
		return fmt.Sprintf("agent/go:1.21-%s", dateSuffix), nil
	case "deno":
		return fmt.Sprintf("agent/deno:1.40-%s", dateSuffix), nil
	default:
		return "", errUnsupportedLang
	}
}

func prepareStorage(vmID string, persist bool) (StorageLayout, error) {
	root := filepath.Join(stateRoot(), "vms", vmID)
	inDir := filepath.Join(root, "in")
	outDir := filepath.Join(root, "out")

	dirs := []string{root, inDir, outDir}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o750); err != nil {
			return StorageLayout{}, err
		}
	}

	layout := StorageLayout{
		Root:        root,
		InputPath:   inDir,
		OutputPath:  outDir,
		StateDBPath: filepath.Join(stateRoot(), stateDBFileName),
		GuestUID:    defaultGuestUIDGID,
		GuestGID:    defaultGuestUIDGID,
	}

	if persist {
		layout.PersistPath = filepath.Join(stateRoot(), "persist", vmID)
		if err := os.MkdirAll(layout.PersistPath, 0o750); err != nil {
			return StorageLayout{}, err
		}
	}

	return layout, nil
}

func ensureStorageLayout(layout StorageLayout) error {
	dirs := []string{layout.Root, layout.InputPath, layout.OutputPath}
	for _, dir := range dirs {
		if dir == "" {
			continue
		}
		if err := os.MkdirAll(dir, 0o750); err != nil {
			return err
		}
	}
	if layout.PersistPath != "" {
		if err := os.MkdirAll(layout.PersistPath, 0o750); err != nil {
			return err
		}
	}
	return nil
}

func stateRoot() string {
	stateRootOnce.Do(func() {
		resolvedStateRoot = computeStateRoot()
	})
	return resolvedStateRoot
}

func computeStateRoot() string {
	if override := strings.TrimSpace(os.Getenv("AGENT_STATE_DIR")); override != "" {
		return override
	}

	if tryEnsureDir(defaultSystemStateRoot) {
		return defaultSystemStateRoot
	}

	if cfgDir, err := os.UserConfigDir(); err == nil {
		candidate := filepath.Join(cfgDir, stateDirName)
		if tryEnsureDir(candidate) {
			return candidate
		}
	}

	if homeDir, err := os.UserHomeDir(); err == nil {
		candidate := filepath.Join(homeDir, "."+stateDirName)
		if tryEnsureDir(candidate) {
			return candidate
		}
	}

	candidate := filepath.Join(os.TempDir(), stateDirName)
	_ = os.MkdirAll(candidate, 0o750)
	return candidate
}

func tryEnsureDir(path string) bool {
	if strings.TrimSpace(path) == "" {
		return false
	}
	if err := os.MkdirAll(path, 0o750); err != nil {
		return false
	}
	return true
}

func stageInputFile(src, inDir string) error {
	info, err := os.Stat(src)
	if err != nil {
		return err
	}
	if info.IsDir() {
		return errors.New("input file must not be a directory")
	}

	dest := filepath.Join(inDir, filepath.Base(src))
	return copyFile(src, dest)
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer func() {
		_ = out.Close()
	}()

	if _, err := io.Copy(out, in); err != nil {
		return err
	}

	return out.Sync()
}
