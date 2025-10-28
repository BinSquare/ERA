//go:build !libkrun

package main

import (
	"context"
	"errors"
	"io"
)

var errLibkrunUnavailable = errors.New("libkrun runtime not available in this build")

type stubVMLauncher struct{}

func (s *stubVMLauncher) Launch(ctx context.Context, record VMRecord) error {
	return errLibkrunUnavailable
}

func (s *stubVMLauncher) Stop(ctx context.Context, vmID string) error {
	return errLibkrunUnavailable
}

func (s *stubVMLauncher) Cleanup(ctx context.Context, vmID string) error {
	return errLibkrunUnavailable
}

func (s *stubVMLauncher) Run(ctx context.Context, record VMRecord, opts VMRunOptions, stdout, stderr io.Writer) (int, error) {
	return -1, errLibkrunUnavailable
}

func (s *stubVMLauncher) Shell(ctx context.Context, record VMRecord, shellCmd string, stdin io.Reader, stdout, stderr io.Writer) (int, error) {
	return -1, errLibkrunUnavailable
}

func (s *stubVMLauncher) List(ctx context.Context) ([]string, error) {
	return nil, errLibkrunUnavailable
}

func newLibkrunVMLauncher() (VMLauncher, error) {
	return &stubVMLauncher{}, nil
}
