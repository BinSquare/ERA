package main

/*
#cgo CFLAGS: -I${SRCDIR}/ffi/include
#cgo LDFLAGS: -L${SRCDIR}/ffi/target/debug -lagent_ffi
#include <stdlib.h>
#include "vmlauncher.h"
*/
import "C"
import (
	"context"
	"fmt"
	"unsafe"
)

type VMLauncher interface {
	Launch(context.Context, VMRecord) error
	Stop(context.Context, string) error
	Cleanup(context.Context, string) error
}

func newVMLauncher() VMLauncher {
	return &ffiVMLauncher{}
}

type ffiVMLauncher struct{}

func (l *ffiVMLauncher) Launch(ctx context.Context, record VMRecord) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	cID := C.CString(record.ID)
	defer C.free(unsafe.Pointer(cID))

	cRootfs := C.CString(record.RootFSImage)
	defer C.free(unsafe.Pointer(cRootfs))

	cNetwork := C.CString(record.NetworkMode)
	defer C.free(unsafe.Pointer(cNetwork))

	config := C.AgentVMConfig{
		id:           cID,
		rootfs_image: cRootfs,
		cpu_count:    C.uint(record.CPUCount),
		memory_mib:   C.uint(record.MemoryMiB),
		network_mode: cNetwork,
	}

	if rc := C.agent_launch_vm(&config); rc != 0 {
		return fmt.Errorf("ffi launch failed: rc=%d", int(rc))
	}
	return nil
}

func (l *ffiVMLauncher) Stop(ctx context.Context, vmID string) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	cID := C.CString(vmID)
	defer C.free(unsafe.Pointer(cID))

	if rc := C.agent_stop_vm(cID); rc != 0 {
		return fmt.Errorf("ffi stop failed: rc=%d", int(rc))
	}
	return nil
}

func (l *ffiVMLauncher) Cleanup(ctx context.Context, vmID string) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	cID := C.CString(vmID)
	defer C.free(unsafe.Pointer(cID))

	if rc := C.agent_cleanup_vm(cID); rc != 0 {
		return fmt.Errorf("ffi cleanup failed: rc=%d", int(rc))
	}
	return nil
}
