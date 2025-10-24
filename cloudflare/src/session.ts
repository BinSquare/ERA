/**
 * Session Management with Durable Objects
 * Handles persistent sessions with file storage in R2
 */

import { SessionSetup, SetupResult } from './plugins/types';
import { runSessionSetup } from './plugins/session_setup';

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

    // POST /run - Run code with file injection/extraction
    if (url.pathname === '/run' && request.method === 'POST') {
      return this.handleRun(request);
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
        if (metadata.persistent) {
          await this.injectFiles(vmId, metadata.id, agentStub);
        }

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
        };
        const mergedEnvs = { ...defaultEnvs, ...(env || {}) };

        const runRes = await agentStub.fetch(new Request(`http://agent/api/vm/${vmId}/run`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            command,
            timeout: timeout || 30,
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

  // INJECT: R2 → VM
  async injectFiles(vmId: string, sessionId: string, agentStub: any): Promise<void> {
    const prefix = `sessions/${sessionId}/`;
    const listed = await this.env.SESSIONS_BUCKET.list({ prefix });

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
    }
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
            timeout: 30,
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
