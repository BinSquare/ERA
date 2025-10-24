package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	defaultSystemStateRoot = "/var/lib/agent"
	stateDirName           = "agent"
	stateDBFileName        = "agent.db"
	defaultGuestUIDGID     = 65532

	storageDirPerm       os.FileMode = 0o755
	sharedStoragePerm    os.FileMode = 0o777
	vmStatusProvisioning             = "provisioning"
	vmStatusReady                    = "ready"
	vmStatusRunning                  = "running"
	vmStatusStopped                  = "stopped"
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

type VMRunError struct {
	Result VMRunResult
	Err    error
}

func (e *VMRunError) Error() string {
	if e.Err != nil {
		return e.Err.Error()
	}
	return "vm run failed"
}

func (e *VMRunError) Unwrap() error {
	return e.Err
}

type StorageLayout struct {
	Root                string
	InputPath           string
	OutputPath          string
	PersistPath         string
	StateDBPath         string
	GuestUID            int
	GuestGID            int
	NetworkMode         string
	ReadOnlyRoot        bool
	DisableGuestVolumes bool
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

func NewVMService(logger *Logger, runtimeName string) (*VMService, error) {
	launcher, err := newVMLauncher(runtimeName)
	if err != nil {
		return nil, err
	}

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
		record.Storage = normalizeStorageLayout(record.Storage)
		cache[record.ID] = record
		_ = ensureStorageLayout(record.Storage)
	}

	return &VMService{
		logger:   logger,
		launcher: launcher,
		store:    store,
		cache:    cache,
	}, nil
}

func (s *VMService) Close() error {
	return s.store.Close()
}

func (s *VMService) List(ctx context.Context) ([]VMRecord, error) {
	presentIDs := make(map[string]struct{})
	var listErr error
	if ids, err := s.launcher.List(ctx); err == nil {
		for _, id := range ids {
			presentIDs[id] = struct{}{}
		}
	} else {
		listErr = err
		s.logger.Warn("failed to enumerate krunvm instances", map[string]any{"error": err.Error()})
		presentIDs = nil
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	records := make([]VMRecord, 0, len(s.cache))
	for id, record := range s.cache {
		if presentIDs != nil {
			_, exists := presentIDs[id]
			if !exists && record.Status != vmStatusStopped {
				record.Status = vmStatusStopped
				s.cache[id] = record
				if err := s.store.Save(record); err != nil {
					s.logger.Warn("failed to persist vm status", map[string]any{"vm": id, "error": err.Error()})
				}
			}
			if exists && record.Status == vmStatusStopped {
				record.Status = vmStatusReady
				s.cache[id] = record
				if err := s.store.Save(record); err != nil {
					s.logger.Warn("failed to persist vm status", map[string]any{"vm": id, "error": err.Error()})
				}
			}
		}
		records = append(records, record)
	}

	sort.Slice(records, func(i, j int) bool {
		if records[i].CreatedAt.Equal(records[j].CreatedAt) {
			return records[i].ID < records[j].ID
		}
		return records[i].CreatedAt.Before(records[j].CreatedAt)
	})

	return records, listErr
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

	rootfsCandidates, err := s.resolveRootFSCandidates(language, opts.Image)
	if err != nil {
		return VMRecord{}, err
	}
	if len(rootfsCandidates) == 0 {
		return VMRecord{}, errors.New("no rootfs candidates resolved")
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
		RootFSImage: rootfsCandidates[0],
		CPUCount:    opts.CPUCount,
		MemoryMiB:   opts.MemoryMiB,
		NetworkMode: opts.NetworkMode,
		Persist:     opts.Persist,
		Status:      vmStatusProvisioning,
		Storage:     layout,
		CreatedAt:   time.Now().UTC(),
	}

	var launchErr error
	for idx, candidate := range rootfsCandidates {
		record.RootFSImage = candidate
		launchErr = s.launcher.Launch(ctx, record)
		if launchErr == nil {
			if idx > 0 {
				s.logger.Info("vm rootfs fallback applied", map[string]any{
					"id":      record.ID,
					"rootfs":  candidate,
					"attempt": idx + 1,
				})
			}
			break
		}

		if idx < len(rootfsCandidates)-1 {
			s.logger.Warn("vm launch failed with rootfs candidate", map[string]any{
				"id":      record.ID,
				"rootfs":  candidate,
				"attempt": idx + 1,
				"error":   launchErr.Error(),
			})
		}
	}

	if launchErr != nil {
		_ = os.RemoveAll(layout.Root)
		if opts.Persist && layout.PersistPath != "" {
			_ = os.RemoveAll(layout.PersistPath)
		}
		return VMRecord{}, launchErr
	}

	record.Status = vmStatusReady

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

	switch record.Status {
	case vmStatusReady, vmStatusRunning:
	case vmStatusStopped:
		if err := s.launcher.Launch(ctx, record); err != nil {
			return VMRunResult{}, err
		}
		record.Status = vmStatusReady
	default:
		return VMRunResult{}, errors.New("vm is not available to run commands")
	}

	if opts.File != "" {
		if record.Storage.DisableGuestVolumes {
			return VMRunResult{}, errors.New("file staging requires guest volume sharing")
		}
		if err := stageInputFile(opts.File, record.Storage.InputPath); err != nil {
			return VMRunResult{}, err
		}
	}

	runCtx, cancel := context.WithTimeout(ctx, time.Duration(opts.Timeout)*time.Second)
	defer cancel()

	start := time.Now()

	stdoutPath := filepath.Join(record.Storage.OutputPath, "stdout.log")
	stderrPath := filepath.Join(record.Storage.OutputPath, "stderr.log")

	stdoutFile, err := os.OpenFile(stdoutPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o640)
	if err != nil {
		return VMRunResult{}, err
	}
	defer func() {
		_ = stdoutFile.Close()
	}()

	stderrFile, err := os.OpenFile(stderrPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o640)
	if err != nil {
		return VMRunResult{}, err
	}
	defer func() {
		_ = stderrFile.Close()
	}()

	exitCode, runErr := s.launcher.Run(runCtx, record, opts, stdoutFile, stderrFile)
	if runErr != nil {
		var cmdErr *commandError
		if !errors.As(runErr, &cmdErr) {
			return VMRunResult{}, runErr
		}

		if isMissingVMError(cmdErr) {
			s.logger.Warn("vm missing from krunvm, recreating", map[string]any{
				"vm":       record.ID,
				"language": record.Language,
			})

			if err := s.launcher.Launch(ctx, record); err != nil {
				return VMRunResult{}, err
			}
			record.Status = vmStatusReady

			if err := truncateAndRewind(stdoutFile); err != nil {
				return VMRunResult{}, err
			}
			if err := truncateAndRewind(stderrFile); err != nil {
				return VMRunResult{}, err
			}

			exitCode, runErr = s.launcher.Run(runCtx, record, opts, stdoutFile, stderrFile)
			if runErr != nil {
				if !errors.As(runErr, &cmdErr) {
					return VMRunResult{}, runErr
				}
			}
		}
	}

	duration := time.Since(start)

	record.LastRunAt = time.Now().UTC()
	record.Status = vmStatusReady

	if err := s.store.Save(record); err != nil {
		return VMRunResult{}, err
	}

	s.mu.Lock()
	s.cache[record.ID] = record
	s.mu.Unlock()

	result := VMRunResult{
		ExitCode:   exitCode,
		StdoutPath: stdoutPath,
		StderrPath: stderrPath,
		Duration:   duration,
	}

	if exitCode != 0 {
		wrappedErr := fmt.Errorf("command exited with code %d", exitCode)
		if runErr != nil {
			wrappedErr = fmt.Errorf("command exited with code %d: %w", exitCode, runErr)
		}
		return result, &VMRunError{
			Result: result,
			Err:    wrappedErr,
		}
	}

	return result, nil
}

func (s *VMService) Stop(ctx context.Context, vmID string) error {
	record, err := s.fetchRecord(vmID)
	if err != nil {
		return err
	}

	if err := s.launcher.Stop(ctx, vmID); err != nil {
		if errors.Is(err, errVMNotFound) {
			record.Status = vmStatusStopped
		} else {
			return err
		}
	} else {
		record.Status = vmStatusStopped
	}

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
		if !errors.Is(err, errVMNotFound) {
			return err
		}
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

func (s *VMService) resolveRootFSCandidates(language, override string) ([]string, error) {
	if override != "" {
		return []string{override}, nil
	}

	switch language {
	case "python":
		return []string{"docker.io/library/python:3.11-slim"}, nil
	case "node", "javascript", "js":
		return []string{"docker.io/library/node:20-slim"}, nil
	case "ruby":
		return []string{"docker.io/library/ruby:3.2-slim"}, nil
	case "golang", "go":
		return []string{"docker.io/library/golang:1.22-bookworm"}, nil
	default:
		return nil, errUnsupportedLang
	}
}

func isMissingVMError(err *commandError) bool {
	if err == nil {
		return false
	}
	combined := strings.ToLower(err.stdout + " " + err.stderr)
	return strings.Contains(combined, "no vm found")
}

func truncateAndRewind(f *os.File) error {
	if err := f.Truncate(0); err != nil {
		return err
	}
	_, err := f.Seek(0, 0)
	return err
}

func prepareStorage(vmID string, persist bool) (StorageLayout, error) {
	root := filepath.Join(stateRoot(), "vms", vmID)
	inDir := filepath.Join(root, "in")
	outDir := filepath.Join(root, "out")
	vmsRoot := filepath.Join(stateRoot(), "vms")
	if err := ensureDir(stateRoot()); err != nil {
		return StorageLayout{}, err
	}
	if err := ensureDir(vmsRoot); err != nil {
		return StorageLayout{}, err
	}

	dirs := []string{root, inDir, outDir}

	for _, dir := range dirs {
		if err := ensureDir(dir); err != nil {
			return StorageLayout{}, err
		}
	}
	layout := StorageLayout{
		Root:                root,
		InputPath:           inDir,
		OutputPath:          outDir,
		StateDBPath:         filepath.Join(stateRoot(), stateDBFileName),
		GuestUID:            defaultGuestUIDGID,
		GuestGID:            defaultGuestUIDGID,
		DisableGuestVolumes: !guestVolumeSharingEnabled(),
	}

	if !layout.DisableGuestVolumes {
		if err := os.Chmod(inDir, sharedStoragePerm); err != nil {
			return StorageLayout{}, err
		}
		if err := os.Chmod(outDir, sharedStoragePerm); err != nil {
			return StorageLayout{}, err
		}
	}

	if persist {
		persistRoot := filepath.Join(stateRoot(), "persist")
		if err := ensureDir(persistRoot); err != nil {
			return StorageLayout{}, err
		}
		layout.PersistPath = filepath.Join(persistRoot, vmID)
		if err := ensureDir(layout.PersistPath); err != nil {
			return StorageLayout{}, err
		}
		if !layout.DisableGuestVolumes {
			if err := os.Chmod(layout.PersistPath, sharedStoragePerm); err != nil {
				return StorageLayout{}, err
			}
		}
	}

	return layout, nil
}

func ensureStorageLayout(layout StorageLayout) error {
	layout = normalizeStorageLayout(layout)
	if layout.Root != "" {
		if err := ensureDir(filepath.Dir(layout.Root)); err != nil {
			return err
		}
	}
	if layout.PersistPath != "" {
		if err := ensureDir(filepath.Dir(layout.PersistPath)); err != nil {
			return err
		}
	}
	dirs := []string{layout.Root, layout.InputPath, layout.OutputPath}
	for _, dir := range dirs {
		if dir == "" {
			continue
		}
		if err := ensureDir(dir); err != nil {
			return err
		}
	}
	if !layout.DisableGuestVolumes {
		if layout.InputPath != "" {
			if err := os.Chmod(layout.InputPath, sharedStoragePerm); err != nil {
				return err
			}
		}
		if layout.OutputPath != "" {
			if err := os.Chmod(layout.OutputPath, sharedStoragePerm); err != nil {
				return err
			}
		}
		if layout.PersistPath != "" {
			if err := ensureDir(layout.PersistPath); err != nil {
				return err
			}
			if err := os.Chmod(layout.PersistPath, sharedStoragePerm); err != nil {
				return err
			}
		}
	}
	return nil
}

func normalizeStorageLayout(layout StorageLayout) StorageLayout {
	if !guestVolumeSharingEnabled() {
		layout.DisableGuestVolumes = true
	} else {
		layout.DisableGuestVolumes = false
	}
	return layout
}

func stateRoot() string {
	stateRootOnce.Do(func() {
		resolvedStateRoot = computeStateRoot()
	})
	return resolvedStateRoot
}

func guestVolumeSharingEnabled() bool {
	raw := strings.TrimSpace(os.Getenv("AGENT_ENABLE_GUEST_VOLUMES"))
	if raw == "" {
		return false
	}
	enabled, err := strconv.ParseBool(raw)
	if err != nil {
		return false
	}
	return enabled
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
	_ = ensureDir(candidate)
	return candidate
}

func tryEnsureDir(path string) bool {
	if strings.TrimSpace(path) == "" {
		return false
	}
	if err := ensureDir(path); err != nil {
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
