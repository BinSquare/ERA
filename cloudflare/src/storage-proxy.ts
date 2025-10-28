// Storage Proxy - Provides HTTP API for KV, D1, R2, DO access from sandboxed code

import { Env } from './types';
import { ResourceMetadata } from './storage-registry';

/**
 * Handle KV operations
 * GET    /api/storage/kv/:namespace/:key - Get value
 * PUT    /api/storage/kv/:namespace/:key - Set value
 * DELETE /api/storage/kv/:namespace/:key - Delete value
 * GET    /api/storage/kv/:namespace - List keys (with ?prefix=)
 */
export async function handleKVOperation(
  namespace: string,
  key: string | null,
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.ERA_KV) {
    return new Response(JSON.stringify({ error: 'KV not configured' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const url = new URL(request.url);

  // List keys in namespace
  if (!key && request.method === 'GET') {
    const prefix = `${namespace}:${url.searchParams.get('prefix') || ''}`;
    const limit = parseInt(url.searchParams.get('limit') || '100');

    const result = await env.ERA_KV.list({ prefix, limit });

    return new Response(JSON.stringify({
      keys: result.keys.map(k => ({
        name: k.name.replace(`${namespace}:`, ''),
        metadata: k.metadata,
      })),
      list_complete: result.list_complete,
      cursor: result.cursor,
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (!key) {
    return new Response(JSON.stringify({ error: 'Key required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const fullKey = `${namespace}:${key}`;

  // GET - Read value
  if (request.method === 'GET') {
    const value = await env.ERA_KV.get(fullKey, { type: 'text' });

    if (value === null) {
      return new Response(JSON.stringify({ error: 'Key not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ value }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // PUT - Write value
  if (request.method === 'PUT') {
    const { value, metadata } = await request.json() as { value: string; metadata?: any };

    await env.ERA_KV.put(fullKey, value, { metadata });

    // Register in registry
    await registerResource(env, {
      type: 'kv',
      namespace,
      key,
      size: new Blob([value]).size,
      metadata,
      created_at: '',
      updated_at: '',
    });

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // DELETE - Delete value
  if (request.method === 'DELETE') {
    await env.ERA_KV.delete(fullKey);

    // Unregister from registry
    await unregisterResource(env, 'kv', namespace, key);

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ error: 'Method not allowed' }), {
    status: 405,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Handle D1 operations
 * POST /api/storage/d1/:namespace/query - Execute query
 * POST /api/storage/d1/:namespace/exec  - Execute statement (no results)
 */
export async function handleD1Operation(
  namespace: string,
  operation: string,
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.ERA_D1) {
    return new Response(JSON.stringify({ error: 'D1 not configured' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { sql, params } = await request.json() as { sql: string; params?: any[] };

  try {
    // Prefix table names with namespace
    const namespacedSql = sql.replace(/\b(FROM|JOIN|INTO|TABLE)\s+(\w+)/gi, `$1 ${namespace}_$2`);

    if (operation === 'query') {
      const result = await env.ERA_D1.prepare(namespacedSql).bind(...(params || [])).all();

      return new Response(JSON.stringify({
        success: true,
        results: result.results,
        meta: result.meta,
      }), {
        headers: { 'Content-Type': 'application/json' },
      });
    } else if (operation === 'exec') {
      const result = await env.ERA_D1.prepare(namespacedSql).bind(...(params || [])).run();

      // Register table if CREATE TABLE
      if (namespacedSql.toUpperCase().includes('CREATE TABLE')) {
        const match = namespacedSql.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)/i);
        if (match) {
          await registerResource(env, {
            type: 'd1',
            namespace,
            key: match[1],
            created_at: '',
            updated_at: '',
          });
        }
      }

      return new Response(JSON.stringify({
        success: true,
        meta: result.meta,
      }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ error: 'Invalid operation' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: 'D1 query failed',
      details: error instanceof Error ? error.message : String(error),
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

/**
 * Handle R2 operations
 * GET    /api/storage/r2/:namespace/:key - Get object
 * PUT    /api/storage/r2/:namespace/:key - Put object
 * DELETE /api/storage/r2/:namespace/:key - Delete object
 * GET    /api/storage/r2/:namespace - List objects (with ?prefix=)
 */
export async function handleR2Operation(
  namespace: string,
  key: string | null,
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.ERA_R2) {
    return new Response(JSON.stringify({ error: 'R2 not configured' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const url = new URL(request.url);

  // List objects in namespace
  if (!key && request.method === 'GET') {
    const prefix = `${namespace}/${url.searchParams.get('prefix') || ''}`;
    const limit = parseInt(url.searchParams.get('limit') || '100');

    const result = await env.ERA_R2.list({ prefix, limit });

    return new Response(JSON.stringify({
      objects: result.objects.map(obj => ({
        key: obj.key.replace(`${namespace}/`, ''),
        size: obj.size,
        uploaded: obj.uploaded.toISOString(),
      })),
      truncated: result.truncated,
      cursor: result.cursor,
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (!key) {
    return new Response(JSON.stringify({ error: 'Key required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const fullKey = `${namespace}/${key}`;

  // GET - Read object
  if (request.method === 'GET') {
    const object = await env.ERA_R2.get(fullKey);

    if (!object) {
      return new Response(JSON.stringify({ error: 'Object not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // Return as base64 for JSON transport
    const arrayBuffer = await object.arrayBuffer();
    const base64 = btoa(String.fromCharCode(...new Uint8Array(arrayBuffer)));

    return new Response(JSON.stringify({
      content: base64,
      size: object.size,
      httpMetadata: object.httpMetadata,
      customMetadata: object.customMetadata,
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // PUT - Write object
  if (request.method === 'PUT') {
    const { content, metadata } = await request.json() as {
      content: string; // base64 encoded
      metadata?: Record<string, string>;
    };

    // Decode base64
    const binary = atob(content);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }

    await env.ERA_R2.put(fullKey, bytes, {
      customMetadata: metadata,
    });

    // Register in registry
    await registerResource(env, {
      type: 'r2',
      namespace,
      key,
      size: bytes.length,
      metadata,
      created_at: '',
      updated_at: '',
    });

    return new Response(JSON.stringify({ success: true, size: bytes.length }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // DELETE - Delete object
  if (request.method === 'DELETE') {
    await env.ERA_R2.delete(fullKey);

    // Unregister from registry
    await unregisterResource(env, 'r2', namespace, key);

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ error: 'Method not allowed' }), {
    status: 405,
    headers: { 'Content-Type': 'application/json' },
  });
}

// Helper functions to interact with registry
async function registerResource(env: Env, resource: ResourceMetadata): Promise<void> {
  try {
    const registryStub = env.STORAGE_REGISTRY.get(env.STORAGE_REGISTRY.idFromName('primary'));
    await registryStub.fetch(new Request('http://registry/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(resource),
    }));
  } catch (error) {
    console.error('Failed to register resource:', error);
  }
}

async function unregisterResource(env: Env, type: string, namespace: string, key: string): Promise<void> {
  try {
    const registryStub = env.STORAGE_REGISTRY.get(env.STORAGE_REGISTRY.idFromName('primary'));
    await registryStub.fetch(new Request('http://registry/unregister', {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, namespace, key }),
    }));
  } catch (error) {
    console.error('Failed to unregister resource:', error);
  }
}
