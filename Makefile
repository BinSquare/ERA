BIN := agent
GO_SOURCES := $(wildcard *.go)
FFI_MANIFEST := ffi/Cargo.toml

TEST_STATE_DIR ?= $(CURDIR)/.agent_state
VM_LANGUAGE ?= python
VM_IMAGE ?=
VM_CPU ?= 1
VM_MEM ?= 256
VM_NETWORK ?= none
VM_PERSIST ?= false

VM_CREATE_ARGS := --language $(VM_LANGUAGE) --cpu $(VM_CPU) --mem $(VM_MEM) --network $(VM_NETWORK)
ifneq ($(strip $(VM_IMAGE)),)
VM_CREATE_ARGS += --image $(VM_IMAGE)
endif
ifeq ($(strip $(VM_PERSIST)),true)
VM_CREATE_ARGS += --persist
endif

.PHONY: all agent ffi fmt clean test

all: agent

agent: ffi $(GO_SOURCES)
	mkdir -p .cache/go-build
	GOCACHE=$(PWD)/.cache/go-build go build -o $(BIN) .

ffi:
	cargo build --manifest-path $(FFI_MANIFEST)

fmt:
	gofmt -w $(GO_SOURCES)

clean:
	rm -f $(BIN)
	cargo clean --manifest-path $(FFI_MANIFEST)
	rm -rf .cache

test: agent
	mkdir -p $(TEST_STATE_DIR)
	AGENT_STATE_DIR=$(TEST_STATE_DIR) ./$(BIN) vm create $(VM_CREATE_ARGS)
