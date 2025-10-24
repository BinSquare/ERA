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

.PHONY: all agent ffi fmt clean test serve docker-build docker-run docker-stop docker-clean

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

# HTTP Server targets
serve: agent
	@echo "Starting HTTP server on port 8787..."
	AGENT_MODE=http PORT=8787 ./$(BIN)

serve-dev: agent
	@echo "Starting HTTP server with debug logging..."
	AGENT_MODE=http PORT=8787 AGENT_LOG_LEVEL=debug ./$(BIN)

# Test HTTP endpoints
test-http:
	@echo "Testing health endpoint..."
	@curl -s http://localhost:8787/health | jq .
	@echo "\nTesting VM creation..."
	@curl -s -X POST http://localhost:8787/api/vm \
		-H "Content-Type: application/json" \
		-d '{"language":"python","cpu_count":1,"memory_mib":256}' | jq .
	@echo "\nListing VMs..."
	@curl -s http://localhost:8787/api/vms | jq .

# Docker targets
docker-build:
	docker build -t era-agent:latest .

docker-run:
	docker run -d \
		--name era-agent \
		-p 8787:8787 \
		-v era-agent-state:/var/lib/agent \
		era-agent:latest

docker-stop:
	docker stop era-agent || true
	docker rm era-agent || true

docker-clean: docker-stop
	docker rmi era-agent:latest || true
	docker volume rm era-agent-state || true

# Docker Compose targets
docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

docker-logs:
	docker-compose logs -f

# Cloudflare deployment helpers
cf-build:
	@echo "Building for Cloudflare Containers..."
	docker build -t era-agent:cloudflare .
	@echo "Tag and push to your registry:"
	@echo "  docker tag era-agent:cloudflare your-registry/era-agent:latest"
	@echo "  docker push your-registry/era-agent:latest"
