# Multi-stage Dockerfile for ERA Agent
# Supports both local Docker and Cloudflare Containers
# Updated for krunvm-based architecture (no FFI/Rust layer needed)

# Stage 1: Build Go binary
FROM golang:1.21-alpine as go-builder

WORKDIR /build

# Install build dependencies
RUN apk add --no-cache gcc musl-dev

# Copy Go module files
COPY go.mod go.sum ./
RUN go mod download

# Copy Go source files
COPY *.go ./

# Build Go binary
# Note: The new architecture uses krunvm for VM management (not FFI)
# In Docker/Cloudflare environments, we use the simpler runtime approach
ENV CGO_ENABLED=0
RUN go build -o agent \
    -ldflags="-s -w" \
    .


# Stage 2: Runtime container - Using Debian for glibc compatibility
FROM debian:12-slim

WORKDIR /app

# Install runtime dependencies including Python, Node.js, and Deno for code execution
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    python3 \
    python3-pip \
    curl \
    unzip \
    golang \
    wget \
    libc6 \
    libgcc-s1 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Deno using official install script
RUN curl -fsSL https://deno.land/install.sh | sh && \
    mv /root/.deno/bin/deno /usr/local/bin/deno && \
    rm -rf /root/.deno

# Remove PEP 668 protection to allow pip installs (safe in isolated VMs)
RUN rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED || true

# Create state directory
RUN mkdir -p /var/lib/agent && \
    chmod 750 /var/lib/agent

# Copy binary from builder
COPY --from=go-builder /build/agent /app/agent

# Set environment variables
ENV AGENT_MODE=http \
    PORT=8787 \
    AGENT_LOG_LEVEL=info \
    AGENT_STATE_DIR=/var/lib/agent

# Expose port
EXPOSE 8787

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8787/health || exit 1

# Run as non-root user
RUN groupadd -g 1000 agent && \
    useradd -u 1000 -g agent -s /bin/bash -m agent && \
    mkdir -p /home/agent/.local/bin /home/agent/.local/lib/python3.11/site-packages && \
    mkdir -p /root/.local/lib/python3.11/site-packages && \
    chmod 755 /root && \
    chmod -R 755 /root/.local && \
    chown -R agent:agent /app /var/lib/agent /home/agent/.local

USER agent

# Configure PATH for user-installed packages (pip, npm global) - must be after USER agent
ENV PATH="/home/agent/.local/bin:$PATH" \
    PYTHONPATH="/home/agent/.local/lib/python3.11/site-packages:$PYTHONPATH" \
    PIP_USER_BASE="/home/agent/.local" \
    PYTHONUSERBASE="/home/agent/.local" \
    NODE_PATH="/home/agent/.local/lib/node_modules:$NODE_PATH"

# Start the server
CMD ["/app/agent", "server", "--addr", ":8787"]

