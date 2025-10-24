package main

import (
	"context"
	"fmt"
	"io"
	"strings"
)

const (
	vmRuntimeKrunVM  = "krunvm"
	vmRuntimeLibkrun = "libkrun"
)

// VMLauncher defines the backend-specific lifecycle operations for managing VMs.
// Implementations can be backed by krunvm, libkrun, or any other virtualization
// runtime that can satisfy the contract.
type VMLauncher interface {
	Launch(context.Context, VMRecord) error
	Stop(context.Context, string) error
	Cleanup(context.Context, string) error
	Run(context.Context, VMRecord, VMRunOptions, io.Writer, io.Writer) (int, error)
	Shell(context.Context, VMRecord, string, io.Reader, io.Writer, io.Writer) (int, error)
	List(context.Context) ([]string, error)
}

// newVMLauncher constructs a VMLauncher implementation based on the requested runtime.
// An empty runtime name defaults to krunvm for backwards compatibility.
func newVMLauncher(runtimeName string) (VMLauncher, error) {
	runtime := strings.ToLower(strings.TrimSpace(runtimeName))
	switch runtime {
	case "", vmRuntimeKrunVM:
		return newKrunVMLauncher(), nil
	case vmRuntimeLibkrun:
		return newLibkrunVMLauncher()
	default:
		return nil, fmt.Errorf("unsupported vm runtime %q", runtimeName)
	}
}
