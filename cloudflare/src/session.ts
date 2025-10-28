/**
 * Session Management with Durable Objects
 * Handles persistent sessions with file storage in R2
 */

import { SessionSetup, SetupResult } from './plugins/types';
import { runSessionSetup } from './plugins/session_setup';
import { PYTHON_SDK, JAVASCRIPT_SDK } from './sdk/sdk-content';

export interface SessionMetadata {
  id: string;
  created_at: string;
  last_run_at: string;
  language: string;
  persistent: boolean;
  file_count: number;
  total_size_bytes: number;
  metadata: Record<string, any>;
  data: Record<string, any>;  // Lightweight data persistence (stored in DO, not R2)
  setup?: SessionSetup;  // Package installation and environment setup
  setup_status?: 'pending' | 'running' | 'completed' | 'failed';  // Track async setup progress
  setup_result?: SetupResult;  // Result of setup execution
  allowInternetAccess?: boolean;  // Allow outbound requests (default: true)
  allowPublicAccess?: boolean;    // Allow inbound requests via proxy (default: true)
  default_timeout?: number;       // Default timeout in seconds for code execution (default: 30)
}

export class SessionDO {
  state: DurableObjectState;
  env: Env;

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // GET /metadata - Get session metadata
    if (url.pathname === '/metadata' && request.method === 'GET') {
      const metadata = await this.state.storage.get<SessionMetadata>('metadata');
      if (!metadata) {
        return new Response(JSON.stringify({ error: 'Session not found' }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify(metadata), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // POST /update - Update metadata
    if (url.pathname === '/update' && request.method === 'POST') {
      const updates = await request.json();
      const metadata = (await this.state.storage.get<SessionMetadata>('metadata')) || {};
      const updated = { ...metadata, ...updates };
      await this.state.storage.put('metadata', updated);
      return new Response(JSON.stringify(updated), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // POST /run-setup - Run package installation asynchronously
    if (url.pathname === '/run-setup' && request.method === 'POST') {
      return this.handleRunSetup(request);
    }

    // POST /run - Run code with file injection/extraction
    if (url.pathname === '/run' && request.method === 'POST') {
      return this.handleRun(request);
    }

    // POST /stream - Run code with streaming output (SSE)
    if (url.pathname === '/stream' && request.method === 'POST') {
      return this.handleRunStream(request);
    }

    // POST /proxy - Forward HTTP request to container
    if (url.pathname === '/proxy' && request.method === 'POST') {
      return this.handleProxy(request);
    }

    return new Response('Not found', { status: 404 });
  }

  async handleRun(request: Request): Promise<Response> {
    try {
      const { code, timeout, env } = await request.json() as {
        code: string;
        timeout?: number;
        env?: Record<string, string>;
      };
      const metadata = await this.state.storage.get<SessionMetadata>('metadata');

      if (!metadata) {
        return new Response(JSON.stringify({ error: 'Session not initialized' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      // Get agent stub
      const agentStub = this.env.ERA_AGENT.get(this.env.ERA_AGENT.idFromName('primary'));

      // Map TypeScript to node for VM creation (TypeScript runs on Node.js)
      const vmLanguage = metadata.language === 'typescript' ? 'node' : metadata.language;

      // 1. Create temporary VM
      const createRes = await agentStub.fetch(new Request('http://agent/api/vm', {
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

      if (!createRes.ok) {
        const error = await createRes.text();
        return new Response(JSON.stringify({ error: 'Failed to create VM', details: error }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      const { id: vmId } = await createRes.json() as { id: string };

      try {
        // 2. INJECT: Upload files from R2 to VM
        // Inject if persistent OR if setup was completed (has installed packages)
        if (metadata.persistent || metadata.setup_status === 'completed') {
          await this.injectFiles(vmId, metadata.id, agentStub);
        }

        // 2.3. INJECT SDK: Upload storage SDK files to VM
        await this.injectSDKFiles(vmId, agentStub);

        // 2.5. INJECT DATA: Write session data to special file
        await this.injectSessionData(vmId, metadata.data || {}, agentStub);

        // 3. Execute code
        const codeBase64 = btoa(unescape(encodeURIComponent(code)));
        let command: string;

        // Handle languages that need files vs piping
        if (metadata.language === 'typescript') {
          const tmpFile = `/tmp/code_${vmId}.ts`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${tmpFile} && npx -y tsx ${tmpFile} && rm ${tmpFile}"`;
        } else if (metadata.language === 'go') {
          const goFile = `/tmp/main_${vmId}.go`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${goFile} && go run ${goFile} && rm ${goFile}"`;
        } else if (metadata.language === 'deno') {
          const denoFile = `/tmp/code_${vmId}.ts`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${denoFile} && /usr/local/bin/deno run --allow-read --allow-write ${denoFile} && rm ${denoFile}"`;
        } else {
          command = `sh -c "echo '${codeBase64}' | base64 -d | ${getInterpreter(metadata.language)}"`;
        }

        // Merge default environment variables with user-provided ones
        const defaultEnvs = {
          ERA_SESSION: 'true',
          ERA_SESSION_ID: metadata.id,
          ERA_LANGUAGE: metadata.language,
          ERA_STORAGE_URL: this.env.ERA_STORAGE_URL || 'http://host.docker.internal:8787',
        };
        const mergedEnvs = { ...defaultEnvs, ...(env || {}) };

        const runRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/run`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            command,
            timeout: timeout || metadata.default_timeout || 30,
            envs: mergedEnvs,
          }),
        }));

        const result = await runRes.json() as {
          exit_code: number;
          stdout: string;
          stderr: string;
          duration: string;
        };

        // 3.5. EXTRACT DATA: Read session data from VM
        const updatedData = await this.extractSessionData(vmId, agentStub);

        // 4. EXTRACT: Download files from VM to R2
        if (metadata.persistent) {
          await this.extractFiles(vmId, metadata.id, agentStub);
        }

        // 5. Update metadata with new data
        const updatedMetadata = {
          ...metadata,
          last_run_at: new Date().toISOString(),
          data: updatedData !== null ? updatedData : metadata.data,
        };
        await this.state.storage.put('metadata', updatedMetadata);

        return new Response(JSON.stringify({
          ...result,
          session_id: metadata.id,
          data: updatedMetadata.data,
        }), {
          headers: { 'Content-Type': 'application/json' },
        });

      } finally {
        // 6. Always cleanup VM
        await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}`, {
          method: 'DELETE',
        }));
      }

    } catch (error) {
      return new Response(JSON.stringify({
        error: 'Failed to execute code',
        details: error instanceof Error ? error.message : String(error),
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }

  async handleRunSetup(request: Request): Promise<Response> {
    try {
      const { sessionId, language, setup } = await request.json() as {
        sessionId: string;
        language: string;
        setup: SessionSetup;
      };

      // Update status to running immediately
      const metadata = await this.state.storage.get<SessionMetadata>('metadata');
      if (!metadata) {
        return new Response(JSON.stringify({ error: 'Session not found' }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      await this.state.storage.put('metadata', {
        ...metadata,
        setup_status: 'running',
      });

      // Run setup asynchronously (no waitUntil limits in Durable Objects!)
      const agentStub = this.env.ERA_AGENT.get(this.env.ERA_AGENT.idFromName('primary'));

      // Fire and forget - setup continues running
      (async () => {
        try {
          const setupResult = await runSessionSetup(sessionId, language, setup, this.env, agentStub);

          // Update session with result
          const currentMetadata = await this.state.storage.get<SessionMetadata>('metadata');
          await this.state.storage.put('metadata', {
            ...currentMetadata,
            setup_status: setupResult.success ? 'completed' : 'failed',
            setup_result: setupResult,
          });
        } catch (error) {
          console.error(`[Setup] Failed for session ${sessionId}:`, error);
          const currentMetadata = await this.state.storage.get<SessionMetadata>('metadata');
          await this.state.storage.put('metadata', {
            ...currentMetadata,
            setup_status: 'failed',
            setup_result: {
              success: false,
              duration_ms: 0,
              error: error instanceof Error ? error.message : String(error),
            },
          });
        }
      })();

      return new Response(JSON.stringify({ status: 'started' }), {
        headers: { 'Content-Type': 'application/json' },
      });

    } catch (error) {
      return new Response(JSON.stringify({
        error: error instanceof Error ? error.message : 'Setup failed',
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }

  async handleRunStream(request: Request): Promise<Response> {
    try {
      const { code, timeout, env } = await request.json() as {
        code: string;
        timeout?: number;
        env?: Record<string, string>;
      };
      const metadata = await this.state.storage.get<SessionMetadata>('metadata');

      if (!metadata) {
        return new Response(JSON.stringify({ error: 'Session not initialized' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      // Get agent stub
      const agentStub = this.env.ERA_AGENT.get(this.env.ERA_AGENT.idFromName('primary'));

      // Map TypeScript to node for VM creation
      const vmLanguage = metadata.language === 'typescript' ? 'node' : metadata.language;

      // 1. Create temporary VM
      const createRes = await agentStub.fetch(new Request('http://agent/api/vm', {
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

      if (!createRes.ok) {
        const error = await createRes.text();
        return new Response(JSON.stringify({ error: 'Failed to create VM', details: error }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      const { id: vmId } = await createRes.json() as { id: string };

      // 2. INJECT: Upload files from R2 to VM
      if (metadata.persistent) {
        await this.injectFiles(vmId, metadata.id, agentStub);
      }

      // 2.3. INJECT SDK: Upload storage SDK files to VM
      await this.injectSDKFiles(vmId, agentStub);

      // 2.5. INJECT DATA: Write session data to special file
      await this.injectSessionData(vmId, metadata.data || {}, agentStub);

      // 3. Prepare code execution command
      const codeBase64 = btoa(unescape(encodeURIComponent(code)));
      let command: string;

      // Handle languages that need files vs piping
      if (metadata.language === 'typescript') {
        const tmpFile = `/tmp/code_${vmId}.ts`;
        command = `sh -c "echo '${codeBase64}' | base64 -d > ${tmpFile} && npx -y tsx ${tmpFile} && rm ${tmpFile}"`;
      } else if (metadata.language === 'go') {
        const goFile = `/tmp/main_${vmId}.go`;
        command = `sh -c "echo '${codeBase64}' | base64 -d > ${goFile} && go run ${goFile} && rm ${goFile}"`;
      } else if (metadata.language === 'deno') {
        const denoFile = `/tmp/code_${vmId}.ts`;
        command = `sh -c "echo '${codeBase64}' | base64 -d > ${denoFile} && /usr/local/bin/deno run --allow-read --allow-write ${denoFile} && rm ${denoFile}"`;
      } else {
        command = `sh -c "echo '${codeBase64}' | base64 -d | ${getInterpreter(metadata.language)}"`;
      }

      // Merge default environment variables with user-provided ones
      const defaultEnvs = {
        ERA_SESSION: 'true',
        ERA_SESSION_ID: metadata.id,
        ERA_LANGUAGE: metadata.language,
        ERA_STORAGE_URL: this.env.ERA_STORAGE_URL || 'http://host.docker.internal:8787',
      };
      const mergedEnvs = { ...defaultEnvs, ...(env || {}) };

      // 4. Stream code execution
      const streamRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/stream`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          command,
          timeout: timeout || metadata.default_timeout || 30,
          envs: mergedEnvs,
        }),
      }));

      if (!streamRes.ok) {
        // Cleanup VM
        await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}`, { method: 'DELETE' }));
        return new Response(JSON.stringify({ error: 'Failed to stream execution' }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      // 5. Create streaming response with cleanup
      const { readable, writable } = new TransformStream();
      const writer = writable.getWriter();

      // Process stream and cleanup
      (async () => {
        try {
          const reader = streamRes.body?.getReader();
          if (!reader) throw new Error('No stream body');

          const decoder = new TextDecoder();
          let buffer = '';

          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split('\n');
            buffer = lines.pop() || '';

            for (const line of lines) {
              if (line.trim()) {
                await writer.write(new TextEncoder().encode(line + '\n'));
              }
            }
          }

          // Process any remaining buffer
          if (buffer.trim()) {
            await writer.write(new TextEncoder().encode(buffer + '\n'));
          }

        } catch (error) {
          console.error('Stream error:', error);
        } finally {
          // 6. Extract session data after execution
          try {
            const updatedData = await this.extractSessionData(vmId, agentStub);
            if (updatedData !== null) {
              const currentMetadata = await this.state.storage.get<SessionMetadata>('metadata');
              if (currentMetadata) {
                const updatedMetadata = {
                  ...currentMetadata,
                  data: updatedData,
                  last_run_at: new Date().toISOString(),
                };
                await this.state.storage.put('metadata', updatedMetadata);
              }
            }

            // 7. Extract files back to R2
            if (metadata.persistent) {
              await this.extractFiles(vmId, metadata.id, agentStub);
            }
          } catch (extractError) {
            console.error('Failed to extract data:', extractError);
          }

          // 8. Cleanup VM
          await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}`, {
            method: 'DELETE',
          }));

          await writer.close();
        }
      })();

      return new Response(readable, {
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
          'Access-Control-Allow-Origin': '*',
        },
      });

    } catch (error) {
      return new Response(JSON.stringify({
        error: 'Failed to stream code execution',
        details: error instanceof Error ? error.message : String(error),
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }

  // INJECT: R2 → VM
  async injectFiles(vmId: string, sessionId: string, agentStub: any): Promise<void> {
    const prefix = `sessions/${sessionId}/`;
    let cursor: string | undefined;
    let totalFiles = 0;

    console.log(`[Inject] Starting file injection for session ${sessionId}`);

    // Paginate through all files in R2
    do {
      const listed = await this.env.SESSIONS_BUCKET.list({
        prefix,
        cursor,
        limit: 1000,
      });

      console.log(`[Inject] Processing batch of ${listed.objects.length} files (total so far: ${totalFiles})`);

      for (const obj of listed.objects) {
        const path = obj.key.replace(prefix, '');
        const content = await this.env.SESSIONS_BUCKET.get(obj.key);
        if (!content) continue;

        const bytes = await content.arrayBuffer();

        // Upload to VM via Go agent file API
        await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/${path}`, {
          method: 'PUT',
          body: bytes,
        }));
        totalFiles++;
      }

      cursor = listed.truncated ? listed.cursor : undefined;
    } while (cursor);

    console.log(`[Inject] Completed: ${totalFiles} files injected`);
  }

  // EXTRACT: VM → R2
  async extractFiles(vmId: string, sessionId: string, agentStub: any): Promise<void> {
    // List files in VM
    const listRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files`, {
      method: 'GET',
    }));

    if (!listRes.ok) {
      console.error('Failed to list VM files:', await listRes.text());
      return;
    }

    const { files } = await listRes.json() as { files: Array<{ path: string; size: number }> };

    let totalSize = 0;

    for (const file of files) {
      // Download from VM
      const fileRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/${file.path}`, {
        method: 'GET',
      }));

      if (!fileRes.ok) continue;

      const content = await fileRes.arrayBuffer();

      // Upload to R2
      const key = `sessions/${sessionId}/${file.path}`;
      await this.env.SESSIONS_BUCKET.put(key, content);

      totalSize += content.byteLength;
    }

    // Update metadata with file info
    const metadata = await this.state.storage.get<SessionMetadata>('metadata');
    if (metadata) {
      await this.state.storage.put('metadata', {
        ...metadata,
        file_count: files.length,
        total_size_bytes: totalSize,
      });
    }
  }

  // INJECT DATA: Write session data to special file .session_data.json
  async injectSessionData(vmId: string, data: Record<string, any>, agentStub: any): Promise<void> {
    const dataJson = JSON.stringify(data, null, 2);
    const dataBytes = new TextEncoder().encode(dataJson);

    // Upload to VM as .session_data.json
    await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/.session_data.json`, {
      method: 'PUT',
      body: dataBytes,
    }));
  }

  // INJECT SDK: Upload storage SDK files to VM
  async injectSDKFiles(vmId: string, agentStub: any): Promise<void> {
    // Upload SDK files to VM root directory
    const sdkFiles = [
      { path: 'era_storage.py', content: PYTHON_SDK },
      { path: 'era_storage.js', content: JAVASCRIPT_SDK },
    ];

    for (const { path, content } of sdkFiles) {
      const bytes = new TextEncoder().encode(content);

      // Upload to VM root directory
      await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/${path}`, {
        method: 'PUT',
        body: bytes,
      }));
    }
  }

  // EXTRACT DATA: Read session data from VM
  async extractSessionData(vmId: string, agentStub: any): Promise<Record<string, any> | null> {
    try {
      // Try to read .session_data.json from VM
      const fileRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/files/.session_data.json`, {
        method: 'GET',
      }));

      if (!fileRes.ok) {
        // File doesn't exist or error reading - return null to keep existing data
        return null;
      }

      const content = await fileRes.text();
      const data = JSON.parse(content);
      return data;
    } catch (error) {
      console.error('Failed to extract session data:', error);
      return null;
    }
  }

  // PROXY: Forward HTTP request to container by simulating it
  async handleProxy(request: Request): Promise<Response> {
    try {
      const { url, method, headers, body } = await request.json() as {
        url: string;
        method: string;
        headers: Record<string, string>;
        body?: string;
      };

      const metadata = await this.state.storage.get<SessionMetadata>('metadata');
      if (!metadata) {
        return new Response(JSON.stringify({ error: 'Session not initialized' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      // Check if code is stored in metadata.data
      const storedCode = metadata.data?.code as string | undefined;
      if (!storedCode) {
        return new Response(JSON.stringify({
          error: 'No code stored in session',
          hint: 'Use PUT /api/sessions/{id}/code to store code that handles HTTP requests'
        }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      // Get agent stub
      const agentStub = this.env.ERA_AGENT.get(this.env.ERA_AGENT.idFromName('primary'));

      // Map TypeScript to node for VM creation
      const vmLanguage = metadata.language === 'typescript' ? 'node' : metadata.language;

      // Create temporary VM
      const createRes = await agentStub.fetch(new Request('http://agent/api/vm', {
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

      if (!createRes.ok) {
        const error = await createRes.text();
        return new Response(JSON.stringify({ error: 'Failed to create VM', details: error }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        });
      }

      const { id: vmId } = await createRes.json() as { id: string };

      try {
        // Inject files from R2
        if (metadata.persistent) {
          await this.injectFiles(vmId, metadata.id, agentStub);
        }

        // Inject SDK files
        await this.injectSDKFiles(vmId, agentStub);

        // Inject session data
        await this.injectSessionData(vmId, metadata.data || {}, agentStub);

        // Prepare HTTP request details as environment variables
        const codeBase64 = btoa(unescape(encodeURIComponent(storedCode)));
        let command: string;

        // Handle languages
        if (metadata.language === 'typescript') {
          const tmpFile = `/tmp/code_${vmId}.ts`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${tmpFile} && npx -y tsx ${tmpFile} && rm ${tmpFile}"`;
        } else if (metadata.language === 'go') {
          const goFile = `/tmp/main_${vmId}.go`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${goFile} && go run ${goFile} && rm ${goFile}"`;
        } else if (metadata.language === 'deno') {
          const denoFile = `/tmp/code_${vmId}.ts`;
          command = `sh -c "echo '${codeBase64}' | base64 -d > ${denoFile} && /usr/local/bin/deno run --allow-read --allow-write ${denoFile} && rm ${denoFile}"`;
        } else {
          command = `sh -c "echo '${codeBase64}' | base64 -d | ${getInterpreter(metadata.language)}"`;
        }

        // Parse URL to extract components
        const parsedUrl = new URL(url);

        // Pass HTTP request details as environment variables
        const httpEnvs = {
          ERA_SESSION: 'true',
          ERA_SESSION_ID: metadata.id,
          ERA_LANGUAGE: metadata.language,
          ERA_STORAGE_URL: this.env.ERA_STORAGE_URL || 'http://host.docker.internal:8787',
          ERA_HTTP_METHOD: method,
          ERA_HTTP_PATH: parsedUrl.pathname,
          ERA_HTTP_QUERY: parsedUrl.search,
          ERA_HTTP_HEADERS: JSON.stringify(headers),
          ERA_HTTP_BODY: body || '',
          ERA_REQUEST_MODE: 'proxy',  // Signal that this is a proxied request
        };

        const runRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/run`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            command,
            timeout: metadata.default_timeout || 30,
            envs: httpEnvs,
          }),
        }));

        const result = await runRes.json() as {
          exit_code: number;
          stdout: string;
          stderr: string;
          duration: string;
        };

        // Extract updated session data
        const updatedData = await this.extractSessionData(vmId, agentStub);

        // Extract files if persistent
        if (metadata.persistent) {
          await this.extractFiles(vmId, metadata.id, agentStub);
        }

        // Update metadata
        const updatedMetadata = {
          ...metadata,
          last_run_at: new Date().toISOString(),
          data: updatedData !== null ? updatedData : metadata.data,
        };
        await this.state.storage.put('metadata', updatedMetadata);

        // Try to parse stdout as JSON response (convention: code outputs JSON)
        try {
          const responseData = JSON.parse(result.stdout);
          return new Response(JSON.stringify(responseData), {
            status: responseData.status || 200,
            headers: {
              'Content-Type': responseData.contentType || 'application/json',
              ...(responseData.headers || {}),
            },
          });
        } catch {
          // If not JSON, return raw stdout
          return new Response(result.stdout, {
            status: result.exit_code === 0 ? 200 : 500,
            headers: { 'Content-Type': 'text/plain' },
          });
        }

      } finally {
        // Cleanup VM
        await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}`, {
          method: 'DELETE',
        }));
      }

    } catch (error) {
      return new Response(JSON.stringify({
        error: 'Failed to proxy request',
        details: error instanceof Error ? error.message : String(error),
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  }
}

function getInterpreter(language: string): string {
  switch (language) {
    case 'python': return 'python3';
    case 'node': return 'node';
    case 'typescript': return 'npx -y tsx';
    default: throw new Error(`Unsupported language: ${language}`);
  }
}
