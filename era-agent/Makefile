BIN := agent
GO_SOURCES := $(wildcard *.go)
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/agent

TEST_STATE_DIR ?= $(CURDIR)/.agent_state
VM_LANGUAGE ?= python
VM_IMAGE ?=
VM_CPU ?= 1
VM_MEM ?= 256
VM_NETWORK ?= none
VM_PERSIST ?= false

IMAGES_DATE ?= $(shell date +%Y%m%d)
IMAGES_REGISTRY ?= agent

VM_CREATE_ARGS := --language $(VM_LANGUAGE) --cpu $(VM_CPU) --mem $(VM_MEM) --network $(VM_NETWORK)
ifneq ($(strip $(VM_IMAGE)),)
VM_CREATE_ARGS += --image $(VM_IMAGE)
endif
ifeq ($(strip $(VM_PERSIST)),true)
VM_CREATE_ARGS += --persist
endif

.PHONY: all agent fmt clean test image-python install uninstall

all: agent

agent: $(GO_SOURCES)
	mkdir -p .cache/go-build
	GOCACHE=$(PWD)/.cache/go-build go build -o $(BIN) .

fmt:
	gofmt -w $(GO_SOURCES)

clean:
	rm -f $(BIN)
	rm -rf .cache

install: agent
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(BIN) $(DESTDIR)$(BINDIR)/$(BIN)
	install -d $(DESTDIR)$(DATADIR)
	@echo "Installed $(BIN) to $(DESTDIR)$(BINDIR)"
	@echo "Run: brew install krunvm buildah  # Required dependencies"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(BIN)
	@echo "Uninstalled $(BIN) from $(DESTDIR)$(BINDIR)"

test: agent
	mkdir -p $(TEST_STATE_DIR)
	AGENT_STATE_DIR=$(TEST_STATE_DIR) ./$(BIN) vm create $(VM_CREATE_ARGS)

image-python:
	@set -euo pipefail; \
	STATE_DIR="$${AGENT_STATE_DIR:-$$HOME/agentVM}"; \
	KRUNVM_DIR="$STATE_DIR/krunvm"; \
	CONTAINERS_DIR="$STATE_DIR/containers"; \
	GRAPHROOT="$CONTAINERS_DIR/storage"; \
	RUNROOT="$CONTAINERS_DIR/runroot"; \
	STORAGE_CONF="$CONTAINERS_DIR/storage.conf"; \
	POLICY_JSON="$CONTAINERS_DIR/policy.json"; \
	REGISTRIES_CONF="$CONTAINERS_DIR/registries.conf"; \
	mkdir -p "$KRUNVM_DIR" "$GRAPHROOT" "$RUNROOT"; \
	if [ ! -f "$STORAGE_CONF" ]; then \
		printf '[storage]\n' >"$STORAGE_CONF"; \
		printf 'driver = "vfs"\n' >>"$STORAGE_CONF"; \
		printf 'graphroot = "%s"\n' "$GRAPHROOT" >>"$STORAGE_CONF"; \
		printf 'runroot = "%s"\n' "$RUNROOT" >>"$STORAGE_CONF"; \
		printf 'rootless_storage_path = "%s"\n' "$GRAPHROOT" >>"$STORAGE_CONF"; \
	fi; \
	if [ ! -f "$POLICY_JSON" ]; then \
		printf '{\n' >"$POLICY_JSON"; \
		printf '  "default": [\n' >>"$POLICY_JSON"; \
		printf '    {\n' >>"$POLICY_JSON"; \
		printf '      "type": "insecureAcceptAnything"\n' >>"$POLICY_JSON"; \
		printf '    }\n' >>"$POLICY_JSON"; \
		printf '  ],\n' >>"$POLICY_JSON"; \
		printf '  "transports": {\n' >>"$POLICY_JSON"; \
		printf '    "docker": {\n' >>"$POLICY_JSON"; \
		printf '      "": [\n' >>"$POLICY_JSON"; \
		printf '        {\n' >>"$POLICY_JSON"; \
		printf '          "type": "insecureAcceptAnything"\n' >>"$POLICY_JSON"; \
		printf '        }\n' >>"$POLICY_JSON"; \
		printf '      ]\n' >>"$POLICY_JSON"; \
		printf '    }\n' >>"$POLICY_JSON"; \
		printf '  }\n' >>"$POLICY_JSON"; \
		printf '}\n' >>"$POLICY_JSON"; \
	fi; \
	if [ ! -f "$REGISTRIES_CONF" ]; then \
		printf 'unqualified-search-registries = ["localhost", "docker.io"]\n\n' >"$REGISTRIES_CONF"; \
		printf '[[registry]]\n' >>"$REGISTRIES_CONF"; \
		printf 'prefix = "docker.io"\n' >>"$REGISTRIES_CONF"; \
		printf 'location = "registry-1.docker.io"\n' >>"$REGISTRIES_CONF"; \
		printf 'blocked = false\n' >>"$REGISTRIES_CONF"; \
		printf 'insecure = false\n' >>"$REGISTRIES_CONF"; \
	fi; \
	CONTAINERS_STORAGE_CONF="$STORAGE_CONF" \
	CONTAINERS_STORAGE_CONFIG="$STORAGE_CONF" \
	STORAGE_CONF="$STORAGE_CONF" \
	BUILDAH_STORAGE_CONF="$STORAGE_CONF" \
	CONTAINERS_POLICY="$POLICY_JSON" \
	SIGNATURE_POLICY="$POLICY_JSON" \
	BUILDAH_SIGNATURE_POLICY="$POLICY_JSON" \
	CONTAINERS_REGISTRIES_CONF="$REGISTRIES_CONF" \
	REGISTRIES_CONFIG_PATH="$REGISTRIES_CONF" \
	BUILDAH_REGISTRIES_CONF="$REGISTRIES_CONF" \
	XDG_CONFIG_HOME="$STATE_DIR" \
	KRUNVM_DATA_DIR="$KRUNVM_DIR" \
	buildah bud \
		--arch amd64 \
		--os linux \
		--signature-policy "$POLICY_JSON" \
		--registries-conf "$REGISTRIES_CONF" \
		-t $(IMAGES_REGISTRY)/python:3.11-$(IMAGES_DATE) \
		scripts/images/python-hello
