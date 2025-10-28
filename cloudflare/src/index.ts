import { Container, loadBalance } from '@cloudflare/containers';
import { SessionDO, SessionMetadata } from './session';
import { SessionSetup } from './plugins/types';
import { handleMCPRequest } from './mcp/server';
import { handleKVOperation, handleD1Operation, handleR2Operation } from './storage-proxy';
import { StorageRegistry } from './storage-registry';
import { Env } from './types';

// Re-export for Durable Objects
export { SessionDO, StorageRegistry };
export type { Env };

/**
 * ERA Agent Container Class
 * Defines how the Go agent container should run
 */
export class EraAgent extends Container {
  defaultPort = 8787;           // Port your Go server listens on
  sleepAfter = '5m';            // Stop container after 5 minutes of inactivity (was 2h)
  
  override onStart() {
    console.log('ERA Agent container started');
  }
  
  override onStop() {
    console.log('ERA Agent container stopped');
  }
  
  override onError(error: unknown) {
    console.error('ERA Agent container error:', error);
  }
}

/**
 * Main Worker Request Handler
 * Handles orchestration and routes to the Go agent container
 */
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // Handle MCP protocol endpoints
    if (url.pathname.startsWith('/mcp/')) {
      return handleMCPRequest(request, env, ctx);
    }

    // Use a fixed ID to get the same container instance every time
    // This ensures BoltDB state is consistent across requests
    const durableObjectId = env.ERA_AGENT.idFromName("primary");
    const stub = env.ERA_AGENT.get(durableObjectId);

    // Handle /api/execute orchestration endpoint (ephemeral)
    if (url.pathname === '/api/execute' && request.method === 'POST') {
      return handleExecute(request, stub);
    }

    // Session endpoints (persistent)

    // GET /api/sessions - List all sessions
    if (url.pathname === '/api/sessions' && request.method === 'GET') {
      return handleListSessions(env);
    }

    // POST /api/sessions - Create new session
    if (url.pathname === '/api/sessions' && request.method === 'POST') {
      return handleCreateSession(request, env, ctx);
    }

    // DELETE /api/sessions - Delete all sessions
    if (url.pathname === '/api/sessions' && request.method === 'DELETE') {
      return handleDeleteAllSessions(env);
    }

    // Session-specific operations (route to Durable Object)
    if (url.pathname.startsWith('/api/sessions/')) {
      const match = url.pathname.match(/^\/api\/sessions\/([^\/]+)(\/.*)?$/);
      if (!match) return new Response('Not found', { status: 404 });

      const sessionId = match[1];
      const subPath = match[2] || '';

      // GET /api/sessions/{id} - Get session metadata
      if (subPath === '' && request.method === 'GET') {
        return handleGetSession(sessionId, env);
      }

      // POST /api/sessions/{id}/run - Run code in session
      if (subPath === '/run' && request.method === 'POST') {
        return handleSessionRun(sessionId, request, env);
      }

      // POST /api/sessions/{id}/stream - Run code with streaming output (SSE)
      if (subPath === '/stream' && request.method === 'POST') {
        return handleSessionRunStream(sessionId, request, env);
      }

      // POST /api/sessions/{id}/duplicate - Duplicate session
      if (subPath === '/duplicate' && request.method === 'POST') {
        return handleDuplicateSession(sessionId, request, env);
      }

      // GET /api/sessions/{id}/files - List files
      if (subPath === '/files' && request.method === 'GET') {
        return handleListSessionFiles(sessionId, env);
      }

      // GET /api/sessions/{id}/files/{path} - Download file
      if (subPath.startsWith('/files/') && request.method === 'GET') {
        const filePath = subPath.replace('/files/', '');
        return handleDownloadSessionFile(sessionId, filePath, env);
      }

      // PUT /api/sessions/{id}/files/{path} - Upload file
      if (subPath.startsWith('/files/') && request.method === 'PUT') {
        const filePath = subPath.replace('/files/', '');
        return handleUploadSessionFile(sessionId, filePath, request, env);
      }

      // PUT /api/sessions/{id}/code - Update stored code
      if (subPath === '/code' && request.method === 'PUT') {
        return handleUpdateSessionCode(sessionId, request, env);
      }

      // GET /api/sessions/{id}/code - Get stored code
      if (subPath === '/code' && request.method === 'GET') {
        return handleGetSessionCode(sessionId, env);
      }

      // DELETE /api/sessions/{id} - Delete session
      if (subPath === '' && request.method === 'DELETE') {
        return handleDeleteSession(sessionId, env);
      }

      // PATCH /api/sessions/{id} - Update session metadata
      if (subPath === '' && request.method === 'PATCH') {
        return handleUpdateSession(sessionId, request, env);
      }

      // GET /api/sessions/{id}/host - Get public URL for port
      if (subPath.startsWith('/host') && request.method === 'GET') {
        return handleGetHost(sessionId, url.searchParams.get('port'), env, request);
      }
    }

    // Storage Proxy API - KV, D1, R2 access from sandboxed code
    if (url.pathname.startsWith('/api/storage/')) {
      return handleStorageProxyRequest(request, env);
    }

    // Storage Registry API - List/manage all resources
    if (url.pathname.startsWith('/api/resources')) {
      return handleStorageRegistryRequest(request, env);
    }

    // Proxy requests to containers: /proxy/{session_id}/{port}/*
    if (url.pathname.startsWith('/proxy/')) {
      return handleProxyRequest(request, env);
    }

    // For /api/* routes not handled above, pass to Go agent
    if (url.pathname.startsWith('/api/')) {
      return await stub.fetch(request);
    }

    // Health check endpoint - pass to Go agent
    if (url.pathname === '/health') {
      return await stub.fetch(request);
    }

    // Handle additional doc redirects (Astro handles /docs/ → /docs/quickstart-hosted/)
    if (url.pathname === '/docs/quickstart' || url.pathname === '/docs/quickstart/') {
      return Response.redirect(new URL('/docs/quickstart-hosted/', request.url), 301);
    }

    // For non-API routes, serve static assets (Astro site)
    if (env.ASSETS) {
      return await env.ASSETS.fetch(request);
    }

    // Fallback: pass to Go agent
    return await stub.fetch(request);
  },
} satisfies ExportedHandler<Env>;

/**
 * Execute Code Orchestration
 * Handles the complete lifecycle: create VM -> run code -> cleanup
 */
export async function handleExecute(request: Request, agentStub: any): Promise<Response> {
  try {
    const body = await request.json() as {
      code: string;
      language: string;
      timeout?: number;
    };

    // Validate required fields
    if (!body.code) {
      return new Response(JSON.stringify({ error: 'code is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    if (!body.language) {
      return new Response(JSON.stringify({ error: 'language is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const timeout = body.timeout || 30;

    // Normalize language for VM creation
    let vmLanguage = body.language.toLowerCase();
    let normalizedLang = vmLanguage;

    if (vmLanguage === 'js' || vmLanguage === 'javascript' || vmLanguage === 'nodejs') {
      vmLanguage = 'node';
      normalizedLang = 'node';
    } else if (vmLanguage === 'py') {
      vmLanguage = 'python';
      normalizedLang = 'python';
    } else if (vmLanguage === 'ts' || vmLanguage === 'typescript') {
      vmLanguage = 'node'; // TypeScript runs on Node VM
      normalizedLang = 'typescript';
    } else if (vmLanguage === 'golang') {
      vmLanguage = 'go';
      normalizedLang = 'go';
    } else if (vmLanguage === 'deno') {
      vmLanguage = 'node'; // Deno runs on Node VM (has Deno installed)
      normalizedLang = 'deno';
    }

    // Step 1: Create VM
    const createResponse = await agentStub.fetch(new Request('http://agent/api/vm', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        language: vmLanguage,
        cpu_count: 1,
        memory_mib: 256,
        network_mode: 'none',
        persist: false,
      }),
    }));

    if (!createResponse.ok) {
      const error = await createResponse.text();
      return new Response(JSON.stringify({
        error: 'Failed to create VM',
        details: error
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const vmData = await createResponse.json() as { id: string };
    const vmId = vmData.id;

    // Step 2: Run code (with cleanup in finally block)
    try {
      // Determine command based on language
      // Use base64 encoding to transfer code safely, then decode and pipe to interpreter
      const codeBase64 = btoa(unescape(encodeURIComponent(body.code)));
      let command: string;

      switch (normalizedLang) {
        case 'python':
          // Decode and pipe to python3
          command = `sh -c "echo '${codeBase64}' | base64 -d | python3"`;
          break;
        case 'node':
          // Decode and pipe to node
          command = `sh -c "echo '${codeBase64}' | base64 -d | node"`;
          break;
        case 'typescript':
          // TypeScript needs a file, so write it out
          const tmpFile = `/tmp/code_${vmId}.ts`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${tmpFile} && npx -y tsx ${tmpFile} && rm ${tmpFile}"`;
          break;
        case 'go':
          // Go needs a file to run
          const goFile = `/tmp/main_${vmId}.go`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${goFile} && go run ${goFile} && rm ${goFile}"`;
          break;
        case 'deno':
          // Deno needs a file to run (supports both JS and TS natively)
          const denoFile = `/tmp/code_${vmId}.ts`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${denoFile} && /usr/local/bin/deno run --allow-read --allow-write ${denoFile} && rm ${denoFile}"`;
          break;
        default:
          throw new Error(`Unsupported language: ${normalizedLang}`);
      }

      const runResponse = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/run`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          command: command,
          timeout: timeout,
        }),
      }));

      const result = await runResponse.json() as {
        exit_code: number;
        stdout: string;
        stderr: string;
        duration: string;
      };

      // Add language and vm_id to response
      return new Response(JSON.stringify({
        ...result,
        language: normalizedLang,
        vm_id: vmId,
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });

    } finally {
      // Step 3: Always cleanup VM
      await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}`, {
        method: 'DELETE',
      }));
    }

  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Failed to execute code',
      details: error instanceof Error ? error.message : String(error)
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

/**
 * Session Management Handlers
 */

export async function handleCreateSession(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const {
    session_id,
    language,
    persistent = true,
    metadata = {},
    data = {},
    setup,
    allowInternetAccess = true,
    allowPublicAccess = true,
    default_timeout
  } = await request.json() as {
    session_id?: string;
    language: string;
    persistent?: boolean;
    metadata?: Record<string, any>;
    data?: Record<string, any>;
    setup?: SessionSetup;
    allowInternetAccess?: boolean;
    allowPublicAccess?: boolean;
    default_timeout?: number;
  };

  // Validate language
  if (!language) {
    return new Response(JSON.stringify({ error: 'language is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Use provided session_id or generate one
  const sessionId = session_id || `sess_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  // Validate session_id format
  if (session_id) {
    if (!/^[a-zA-Z0-9_-]+$/.test(session_id)) {
      return new Response(JSON.stringify({ error: 'session_id must contain only letters, numbers, hyphens, and underscores' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }

  // Check if session already exists
  const existingId = env.SESSIONS.idFromName(sessionId);
  const existingStub = env.SESSIONS.get(existingId);
  const existingCheck = await existingStub.fetch(new Request('http://session/metadata', { method: 'GET' }));

  if (existingCheck.ok) {
    return new Response(JSON.stringify({ error: 'session id already exists', id: sessionId }), {
      status: 409,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Create Durable Object for this session
  const id = env.SESSIONS.idFromName(sessionId);
  const stub = env.SESSIONS.get(id);

  // Initialize session metadata
  const sessionMetadata: SessionMetadata = {
    id: sessionId,
    created_at: new Date().toISOString(),
    last_run_at: '',
    language,
    persistent,
    file_count: 0,
    total_size_bytes: 0,
    metadata,
    data,
    setup,
    setup_status: setup ? 'pending' : undefined,
    allowInternetAccess,
    allowPublicAccess,
    default_timeout,
  };

  await stub.fetch(new Request('http://session/update', {
    method: 'POST',
    body: JSON.stringify(sessionMetadata),
  }));

  // Run setup asynchronously if provided (install packages, run commands, etc.)
  // Delegate to Durable Object to avoid Worker's 30-second waitUntil limit
  if (setup) {
    // Fire and forget - DO will handle it
    stub.fetch(new Request('http://session/run-setup', {
      method: 'POST',
      body: JSON.stringify({ sessionId, language, setup }),
    })).catch(error => {
      console.error(`[Setup] Failed to start setup for ${sessionId}:`, error);
    });
  }

  // Register session in KV for listing
  await env.SESSIONS_BUCKET.put(`_registry/${sessionId}`, JSON.stringify({
    id: sessionId,
    language,
    created_at: sessionMetadata.created_at,
  }));

  return new Response(JSON.stringify(sessionMetadata), {
    status: 201,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleGetSession(sessionId: string, env: Env): Promise<Response> {
  const id = env.SESSIONS.idFromName(sessionId);
  const stub = env.SESSIONS.get(id);

  return stub.fetch(new Request('http://session/metadata', {
    method: 'GET',
  }));
}

export async function handleSessionRun(sessionId: string, request: Request, env: Env): Promise<Response> {
  const id = env.SESSIONS.idFromName(sessionId);
  const stub = env.SESSIONS.get(id);

  // Parse request body
  const requestBody = await request.text();
  let runConfig = requestBody ? JSON.parse(requestBody) : {};

  // Get session metadata
  const metadataRes = await stub.fetch(new Request('http://session/metadata', { method: 'GET' }));
  let metadata: SessionMetadata | null = null;
  if (metadataRes.ok) {
    metadata = await metadataRes.json() as SessionMetadata;
  }

  // If no code provided, use stored code from session.data.code
  if (!runConfig.code) {
    if (metadata?.data?.code) {
      runConfig.code = metadata.data.code;
    } else {
      return new Response(JSON.stringify({
        error: 'no code provided and no stored code found',
        hint: 'Use PUT /api/sessions/{id}/code to store default code'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }

  // Inject ERA environment variables
  const requestUrl = new URL(request.url);
  const baseUrl = `${requestUrl.protocol}//${requestUrl.host}`;

  const eraEnvVars = {
    ERA_SESSION: 'true',
    ERA_SESSION_ID: sessionId,
    ERA_LANGUAGE: metadata?.language || 'unknown',
    ERA_BASE_URL: baseUrl,
    ERA_PROXY_URL: `${baseUrl}/proxy/${sessionId}`,
  };

  // Merge user env vars with ERA env vars (ERA vars take precedence)
  runConfig.env = {
    ...runConfig.env,
    ...eraEnvVars,
  };

  // Forward to Durable Object which handles inject/run/extract
  return stub.fetch(new Request('http://session/run', {
    method: 'POST',
    body: JSON.stringify(runConfig),
  }));
}

export async function handleSessionRunStream(sessionId: string, request: Request, env: Env): Promise<Response> {
  const id = env.SESSIONS.idFromName(sessionId);
  const stub = env.SESSIONS.get(id);

  // Parse request body
  const requestBody = await request.text();
  let runConfig = requestBody ? JSON.parse(requestBody) : {};

  // Get session metadata
  const metadataRes = await stub.fetch(new Request('http://session/metadata', { method: 'GET' }));
  let metadata: SessionMetadata | null = null;
  if (metadataRes.ok) {
    metadata = await metadataRes.json() as SessionMetadata;
  }

  // If no code provided, use stored code from session.data.code
  if (!runConfig.code) {
    if (metadata?.data?.code) {
      runConfig.code = metadata.data.code;
    } else {
      return new Response(JSON.stringify({
        error: 'no code provided and no stored code found',
        hint: 'Use PUT /api/sessions/{id}/code to store code that handles HTTP requests'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }

  // Inject ERA environment variables
  const requestUrl = new URL(request.url);
  const baseUrl = `${requestUrl.protocol}//${requestUrl.host}`;

  const eraEnvVars = {
    ERA_SESSION: 'true',
    ERA_SESSION_ID: sessionId,
    ERA_LANGUAGE: metadata?.language || 'unknown',
    ERA_BASE_URL: baseUrl,
    ERA_PROXY_URL: `${baseUrl}/proxy/${sessionId}`,
  };

  // Merge user env vars with ERA env vars (ERA vars take precedence)
  runConfig.env = {
    ...runConfig.env,
    ...eraEnvVars,
  };

  // Forward to Durable Object which handles inject/stream/extract
  return stub.fetch(new Request('http://session/stream', {
    method: 'POST',
    body: JSON.stringify(runConfig),
  }));
}

export async function handleListSessionFiles(sessionId: string, env: Env): Promise<Response> {
  const prefix = `sessions/${sessionId}/`;
  const listed = await env.SESSIONS_BUCKET.list({ prefix });

  const files = listed.objects.map(obj => ({
    path: obj.key.replace(prefix, ''),
    size: obj.size,
    uploaded: obj.uploaded,
  }));

  return new Response(JSON.stringify({ files, count: files.length }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleDownloadSessionFile(sessionId: string, filePath: string, env: Env): Promise<Response> {
  const key = `sessions/${sessionId}/${filePath}`;
  const obj = await env.SESSIONS_BUCKET.get(key);

  if (!obj) {
    return new Response('File not found', { status: 404 });
  }

  return new Response(obj.body, {
    headers: {
      'Content-Type': obj.httpMetadata?.contentType || 'application/octet-stream',
      'Content-Length': obj.size.toString(),
    },
  });
}

export async function handleUploadSessionFile(sessionId: string, filePath: string, request: Request, env: Env): Promise<Response> {
  const key = `sessions/${sessionId}/${filePath}`;
  const content = await request.arrayBuffer();

  await env.SESSIONS_BUCKET.put(key, content);

  return new Response(JSON.stringify({
    path: filePath,
    size: content.byteLength,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleUpdateSessionCode(sessionId: string, request: Request, env: Env): Promise<Response> {
  const id = env.SESSIONS.idFromName(sessionId);
  const stub = env.SESSIONS.get(id);

  // Get current metadata
  const metadataRes = await stub.fetch(new Request('http://session/metadata', { method: 'GET' }));
  if (!metadataRes.ok) {
    return new Response(JSON.stringify({ error: 'session not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Parse new code from request
  const body = await request.json() as { code: string; description?: string };
  if (!body.code) {
    return new Response(JSON.stringify({ error: 'code field required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const metadata = await metadataRes.json() as SessionMetadata;

  // Update data.code and optionally data.code_description
  const updatedData = {
    ...metadata.data,
    code: body.code,
    code_description: body.description || metadata.data?.code_description,
    code_updated_at: new Date().toISOString(),
  };

  // Update session
  await stub.fetch(new Request('http://session/update', {
    method: 'POST',
    body: JSON.stringify({ data: updatedData }),
  }));

  return new Response(JSON.stringify({
    success: true,
    code_length: body.code.length,
    updated_at: updatedData.code_updated_at,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleGetSessionCode(sessionId: string, env: Env): Promise<Response> {
  const id = env.SESSIONS.idFromName(sessionId);
  const stub = env.SESSIONS.get(id);

  // Get metadata
  const metadataRes = await stub.fetch(new Request('http://session/metadata', { method: 'GET' }));
  if (!metadataRes.ok) {
    return new Response(JSON.stringify({ error: 'session not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const metadata = await metadataRes.json() as SessionMetadata;

  if (!metadata.data?.code) {
    return new Response(JSON.stringify({
      error: 'no code stored',
      hint: 'Use PUT /api/sessions/{id}/code to store code'
    }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({
    code: metadata.data.code,
    description: metadata.data.code_description,
    updated_at: metadata.data.code_updated_at,
    code_length: metadata.data.code.length,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleDeleteSession(sessionId: string, env: Env): Promise<Response> {
  // Delete all files from R2
  const prefix = `sessions/${sessionId}/`;
  const listed = await env.SESSIONS_BUCKET.list({ prefix });

  for (const obj of listed.objects) {
    await env.SESSIONS_BUCKET.delete(obj.key);
  }

  // Remove from registry
  await env.SESSIONS_BUCKET.delete(`_registry/${sessionId}`);

  // Note: Durable Object will be garbage collected eventually
  // No explicit deletion needed

  return new Response(JSON.stringify({
    success: true,
    id: sessionId,
    deleted_at: new Date().toISOString()
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleUpdateSession(sessionId: string, request: Request, env: Env): Promise<Response> {
  const updates = await request.json() as {
    default_timeout?: number;
    allowInternetAccess?: boolean;
    allowPublicAccess?: boolean;
    metadata?: Record<string, any>;
  };

  // Validate updates
  if (updates.default_timeout !== undefined) {
    if (typeof updates.default_timeout !== 'number' || updates.default_timeout <= 0) {
      return new Response(JSON.stringify({
        error: 'invalid default_timeout',
        message: 'default_timeout must be a positive number'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }

  // Get session stub
  const stub = env.SESSIONS.get(env.SESSIONS.idFromName(sessionId));

  // Update session metadata
  const res = await stub.fetch(new Request('http://session/update', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(updates),
  }));

  if (!res.ok) {
    const error = await res.text();
    return new Response(JSON.stringify({
      error: 'failed to update session',
      details: error
    }), {
      status: res.status,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const metadata = await res.json();

  // Update registry if it exists
  try {
    const registryKey = `_registry/${sessionId}`;
    const existing = await env.SESSIONS_BUCKET.get(registryKey);
    if (existing) {
      const registryData = JSON.parse(await existing.text());
      const updated = {
        ...registryData,
        ...updates,
        updated_at: new Date().toISOString()
      };
      await env.SESSIONS_BUCKET.put(registryKey, JSON.stringify(updated));
    }
  } catch (error) {
    // Registry update failed but session was updated - log warning but don't fail
    console.warn('Failed to update registry:', error);
  }

  return new Response(JSON.stringify({
    success: true,
    id: sessionId,
    metadata,
    updated_at: new Date().toISOString()
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleDeleteAllSessions(env: Env): Promise<Response> {
  // List all sessions from registry
  const prefix = '_registry/';
  const listed = await env.SESSIONS_BUCKET.list({ prefix });

  const deletedSessions: string[] = [];

  // Delete each session
  for (const obj of listed.objects) {
    const sessionId = obj.key.replace('_registry/', '');

    // Delete all files for this session
    const sessionPrefix = `sessions/${sessionId}/`;
    const sessionFiles = await env.SESSIONS_BUCKET.list({ prefix: sessionPrefix });

    for (const file of sessionFiles.objects) {
      await env.SESSIONS_BUCKET.delete(file.key);
    }

    // Remove from registry
    await env.SESSIONS_BUCKET.delete(`_registry/${sessionId}`);

    deletedSessions.push(sessionId);
  }

  return new Response(JSON.stringify({
    success: true,
    deleted_count: deletedSessions.length,
    deleted_sessions: deletedSessions,
    deleted_at: new Date().toISOString()
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleListSessions(env: Env): Promise<Response> {
  // List all sessions from registry
  const prefix = '_registry/';
  const listed = await env.SESSIONS_BUCKET.list({ prefix });

  const sessions = [];
  for (const obj of listed.objects) {
    const content = await env.SESSIONS_BUCKET.get(obj.key);
    if (content) {
      const registryData = JSON.parse(await content.text());
      sessions.push(registryData);
    }
  }

  return new Response(JSON.stringify({
    sessions,
    count: sessions.length,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleDuplicateSession(sessionId: string, request: Request, env: Env): Promise<Response> {
  // Get source session metadata
  const sourceId = env.SESSIONS.idFromName(sessionId);
  const sourceStub = env.SESSIONS.get(sourceId);
  const sourceRes = await sourceStub.fetch(new Request('http://session/metadata', { method: 'GET' }));

  if (!sourceRes.ok) {
    return new Response(JSON.stringify({ error: 'source session not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const sourceMetadata = await sourceRes.json() as SessionMetadata;

  // Get new session ID from request or generate one
  const { id: newId } = await request.json().catch(() => ({})) as { id?: string };
  const newSessionId = newId || `${sessionId}-copy-${Date.now()}`;

  // Validate new ID format
  if (!/^[a-zA-Z0-9_-]+$/.test(newSessionId)) {
    return new Response(JSON.stringify({ error: 'new id must contain only letters, numbers, hyphens, and underscores' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Check if new session already exists
  const existingId = env.SESSIONS.idFromName(newSessionId);
  const existingStub = env.SESSIONS.get(existingId);
  const existingCheck = await existingStub.fetch(new Request('http://session/metadata', { method: 'GET' }));

  if (existingCheck.ok) {
    return new Response(JSON.stringify({ error: 'new session id already exists', id: newSessionId }), {
      status: 409,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Create new session with copied data
  const newMetadata: SessionMetadata = {
    ...sourceMetadata,
    id: newSessionId,
    created_at: new Date().toISOString(),
    last_run_at: '',
  };

  const newStub = env.SESSIONS.get(env.SESSIONS.idFromName(newSessionId));
  await newStub.fetch(new Request('http://session/update', {
    method: 'POST',
    body: JSON.stringify(newMetadata),
  }));

  // Copy files if persistent
  if (sourceMetadata.persistent) {
    const sourcePrefix = `sessions/${sessionId}/`;
    const listed = await env.SESSIONS_BUCKET.list({ prefix: sourcePrefix });

    for (const obj of listed.objects) {
      const content = await env.SESSIONS_BUCKET.get(obj.key);
      if (content) {
        const newKey = obj.key.replace(sourcePrefix, `sessions/${newSessionId}/`);
        await env.SESSIONS_BUCKET.put(newKey, content.body);
      }
    }
  }

  // Register new session
  await env.SESSIONS_BUCKET.put(`_registry/${newSessionId}`, JSON.stringify({
    id: newSessionId,
    language: newMetadata.language,
    created_at: newMetadata.created_at,
  }));

  return new Response(JSON.stringify(newMetadata), {
    status: 201,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Proxy Handler - Forward requests to containers
 * Route: /proxy/{session_id}/{port}/*
 */
async function handleProxyRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  // Parse route: /proxy/{session_id}/{port}/{path}
  const match = url.pathname.match(/^\/proxy\/([^\/]+)\/(\d+)(\/.*)?$/);
  if (!match) {
    return new Response(JSON.stringify({
      error: 'invalid proxy path',
      format: '/proxy/{session_id}/{port}/{path}'
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const [, sessionId, port, path = '/'] = match;

  // Check if session exists and allows public access
  const id = env.SESSIONS.idFromName(sessionId);
  const stub = env.SESSIONS.get(id);
  const metadataRes = await stub.fetch(new Request('http://session/metadata', { method: 'GET' }));

  if (!metadataRes.ok) {
    return new Response(JSON.stringify({ error: 'session not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const metadata = await metadataRes.json() as SessionMetadata;

  // Check if public access is allowed
  if (metadata.allowPublicAccess === false) {
    return new Response(JSON.stringify({
      error: 'public access disabled for this session',
      hint: 'Set allowPublicAccess: true when creating the session'
    }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Forward request to container through Session DO
  // The Session DO has access to the container and can forward the request
  try {
    // Construct the proxy path that the container's server should see
    const containerUrl = `http://localhost:${port}${path}${url.search}`;

    // Forward through the Session DO's proxy endpoint
    const proxyResponse = await stub.fetch(new Request(`http://session/proxy`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        url: containerUrl,
        method: request.method,
        headers: Object.fromEntries(request.headers.entries()),
        body: request.body ? await request.text() : undefined,
      }),
    }));

    return proxyResponse;
  } catch (error) {
    return new Response(JSON.stringify({
      error: 'failed to connect to container',
      details: error instanceof Error ? error.message : String(error),
      hint: 'Make sure a server is running on this port inside the session'
    }), {
      status: 502,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

/**
 * Storage Proxy Request Handler
 * Routes to appropriate storage handler (KV, D1, R2)
 */
async function handleStorageProxyRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  // Parse route: /api/storage/{type}/{namespace}[/{key}]
  const match = url.pathname.match(/^\/api\/storage\/(kv|d1|r2)\/([^\/]+)(?:\/(.+))?$/);
  if (!match) {
    return new Response(JSON.stringify({
      error: 'invalid storage path',
      format: '/api/storage/{kv|d1|r2}/{namespace}[/{key}]'
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const [, type, namespace, key] = match;

  try {
    if (type === 'kv') {
      return await handleKVOperation(namespace, key || null, request, env);
    } else if (type === 'd1') {
      // For D1, the "key" is actually the operation (query/exec)
      return await handleD1Operation(namespace, key || 'query', request, env);
    } else if (type === 'r2') {
      return await handleR2Operation(namespace, key || null, request, env);
    }

    return new Response(JSON.stringify({ error: 'Unknown storage type' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Storage operation failed',
      details: error instanceof Error ? error.message : String(error),
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

/**
 * Storage Registry Request Handler
 * List and manage all resources across KV, D1, R2
 */
async function handleStorageRegistryRequest(request: Request, env: Env): Promise<Response> {
  const registryStub = env.STORAGE_REGISTRY.get(env.STORAGE_REGISTRY.idFromName('primary'));
  return await registryStub.fetch(request);
}

/**
 * Get Host URL Handler
 * Returns the public URL for accessing a port inside the session
 */
async function handleGetHost(sessionId: string, port: string | null, env: Env, request: Request): Promise<Response> {
  if (!port) {
    return new Response(JSON.stringify({
      error: 'port parameter required',
      usage: 'GET /api/sessions/{id}/host?port=3000'
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Validate port number
  const portNum = parseInt(port, 10);
  if (isNaN(portNum) || portNum < 1 || portNum > 65535) {
    return new Response(JSON.stringify({ error: 'invalid port number' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Check if session exists
  const id = env.SESSIONS.idFromName(sessionId);
  const stub = env.SESSIONS.get(id);
  const metadataRes = await stub.fetch(new Request('http://session/metadata', { method: 'GET' }));

  if (!metadataRes.ok) {
    return new Response(JSON.stringify({ error: 'session not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Get request host to build absolute URL
  const requestUrl = new URL(request.url);
  const baseUrl = `${requestUrl.protocol}//${requestUrl.host}`;

  return new Response(JSON.stringify({
    url: `${baseUrl}/proxy/${sessionId}/${port}`,
    base_url: `${baseUrl}/proxy/${sessionId}/${port}`,
    session_id: sessionId,
    port: portNum,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Generate API documentation HTML (unused - kept for reference)
 */
/*
function getDocumentation() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ERA Agent API Documentation</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 1200px;
      margin: 0 auto;
      padding: 20px;
      background: #f5f5f5;
    }
    header {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 40px 20px;
      border-radius: 10px;
      margin-bottom: 30px;
      box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    }
    h1 { font-size: 2.5em; margin-bottom: 10px; }
    .subtitle { font-size: 1.2em; opacity: 0.9; }
    .container {
      background: white;
      padding: 30px;
      border-radius: 10px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      margin-bottom: 20px;
    }
    h2 {
      color: #667eea;
      margin: 30px 0 15px 0;
      padding-bottom: 10px;
      border-bottom: 2px solid #667eea;
    }
    h3 {
      color: #555;
      margin: 20px 0 10px 0;
    }
    .endpoint {
      background: #f8f9fa;
      padding: 20px;
      margin: 15px 0;
      border-left: 4px solid #667eea;
      border-radius: 5px;
    }
    .method {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 4px;
      font-weight: bold;
      font-size: 0.9em;
      margin-right: 10px;
    }
    .get { background: #28a745; color: white; }
    .post { background: #007bff; color: white; }
    .delete { background: #dc3545; color: white; }
    code {
      background: #f4f4f4;
      padding: 2px 6px;
      border-radius: 3px;
      font-family: 'Monaco', 'Courier New', monospace;
      font-size: 0.9em;
    }
    pre {
      background: #2d2d2d;
      color: #f8f8f2;
      padding: 20px;
      border-radius: 5px;
      overflow-x: auto;
      margin: 15px 0;
    }
    pre code {
      background: none;
      color: inherit;
      padding: 0;
    }
    .status {
      display: inline-block;
      padding: 8px 16px;
      background: #28a745;
      color: white;
      border-radius: 20px;
      font-weight: bold;
      margin-bottom: 20px;
    }
    .example {
      margin: 15px 0;
    }
    a {
      color: #667eea;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
  </style>
</head>
<body>
  <header>
    <h1>🚀 ERA Agent</h1>
    <p class="subtitle">VM Orchestration System - API Documentation</p>
  </header>

  <div class="container">
    <span class="status">✓ Service Online</span>
    
    <h2>Overview</h2>
    <p>ERA Agent provides a REST API for creating and managing isolated VM instances for code execution. Built with Go and deployed on Cloudflare's edge network.</p>
    
    <h3>Base URL</h3>
    <code>https://anewera.dev</code>

    <h2>Endpoints</h2>

    <div class="endpoint">
      <span class="method get">GET</span>
      <strong>/health</strong>
      <p>Health check endpoint - verify the service is running</p>
      <div class="example">
        <strong>Example:</strong>
        <pre><code>curl https://anewera.dev/health</code></pre>
      </div>
    </div>

    <div class="endpoint">
      <span class="method post">POST</span>
      <strong>/api/vm</strong>
      <p>Create a new VM instance</p>
      <div class="example">
        <strong>Request Body:</strong>
        <pre><code>{
  "language": "python",
  "cpu_count": 1,
  "memory_mib": 256,
  "network_mode": "none",
  "persist": false
}</code></pre>
        <strong>Example:</strong>
        <pre><code>curl -X POST https://anewera.dev/api/vm \\
  -H "Content-Type: application/json" \\
  -d '{"language":"python","cpu_count":1,"memory_mib":256}'</code></pre>
      </div>
    </div>

    <div class="endpoint">
      <span class="method get">GET</span>
      <strong>/api/vm/{id}</strong>
      <p>Get details about a specific VM</p>
      <div class="example">
        <strong>Example:</strong>
        <pre><code>curl https://anewera.dev/api/vm/python-123456789</code></pre>
      </div>
    </div>

    <div class="endpoint">
      <span class="method post">POST</span>
      <strong>/api/vm/{id}/run</strong>
      <p>Execute code in a VM</p>
      <div class="example">
        <strong>Request Body:</strong>
        <pre><code>{
  "command": "python -c \\"print('Hello World!')\\"",
  "timeout": 30
}</code></pre>
        <strong>Example:</strong>
        <pre><code>curl -X POST https://anewera.dev/api/vm/python-123/run \\
  -H "Content-Type: application/json" \\
  -d '{"command":"python -c \\"print(42)\\"","timeout":30}'</code></pre>
      </div>
    </div>

    <div class="endpoint">
      <span class="method post">POST</span>
      <strong>/api/vm/{id}/stop</strong>
      <p>Stop a running VM</p>
    </div>

    <div class="endpoint">
      <span class="method delete">DELETE</span>
      <strong>/api/vm/{id}</strong>
      <p>Delete a VM and clean up resources</p>
    </div>

    <div class="endpoint">
      <span class="method get">GET</span>
      <strong>/api/vms</strong>
      <p>List all VMs</p>
    </div>

    <h2>Supported Languages</h2>
    <ul>
      <li><strong>Python</strong> - Python 3.11</li>
      <li><strong>Node.js</strong> - Node 20</li>
    </ul>

    <h2>Quick Start</h2>
    <pre><code># 1. Create a VM
VM_ID=$(curl -s -X POST https://anewera.dev/api/vm \\
  -H "Content-Type: application/json" \\
  -d '{"language":"python","cpu_count":1,"memory_mib":256}' | jq -r '.id')

# 2. Run code
curl -X POST https://anewera.dev/api/vm/$VM_ID/run \\
  -H "Content-Type: application/json" \\
  -d '{"command":"python -c \\"print(42)\\"","timeout":30}'

# 3. Clean up
curl -X DELETE https://anewera.dev/api/vm/$VM_ID</code></pre>

    <h2>Rate Limits & Resources</h2>
    <ul>
      <li>Request timeout: 30 seconds (configurable)</li>
      <li>Default memory: 256 MiB</li>
      <li>Default CPU: 1 core</li>
      <li>Network: Isolated by default</li>
    </ul>

    <h2>Need Help?</h2>
    <p>For more information, visit the <a href="https://github.com/yourusername/ERA">GitHub repository</a>.</p>
  </div>
</body>
</html>`;
}
*/
