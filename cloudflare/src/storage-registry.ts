// Storage Registry Durable Object
// Tracks all resources created across KV, D1, R2, DO

export interface ResourceMetadata {
  type: 'kv' | 'd1' | 'r2' | 'do';
  namespace: string;
  key: string; // For KV/R2, or table name for D1, or DO id
  created_at: string;
  updated_at: string;
  size?: number; // Bytes (for R2/KV)
  metadata?: Record<string, any>; // Custom metadata
}

export interface ResourceQuery {
  type?: 'kv' | 'd1' | 'r2' | 'do';
  namespace?: string;
  key_prefix?: string;
  limit?: number;
  offset?: number;
}

export class StorageRegistry {
  private state: DurableObjectState;
  private resources: Map<string, ResourceMetadata>;

  constructor(state: DurableObjectState) {
    this.state = state;
    this.resources = new Map();
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // Initialize from storage on first request
    if (this.resources.size === 0) {
      const stored = await this.state.storage.get<Record<string, ResourceMetadata>>('resources');
      if (stored) {
        this.resources = new Map(Object.entries(stored));
      }
    }

    // POST /register - Register a new resource
    if (url.pathname === '/register' && request.method === 'POST') {
      const resource = await request.json() as ResourceMetadata;
      return this.registerResource(resource);
    }

    // DELETE /unregister - Unregister a resource
    if (url.pathname === '/unregister' && request.method === 'DELETE') {
      const { type, namespace, key } = await request.json() as { type: string; namespace: string; key: string };
      return this.unregisterResource(type, namespace, key);
    }

    // GET /list - List resources with optional filters
    if (url.pathname === '/list' && request.method === 'GET') {
      const query: ResourceQuery = {
        type: url.searchParams.get('type') as any,
        namespace: url.searchParams.get('namespace') || undefined,
        key_prefix: url.searchParams.get('key_prefix') || undefined,
        limit: parseInt(url.searchParams.get('limit') || '100'),
        offset: parseInt(url.searchParams.get('offset') || '0'),
      };
      return this.listResources(query);
    }

    // GET /stats - Get statistics
    if (url.pathname === '/stats' && request.method === 'GET') {
      return this.getStats();
    }

    return new Response('Not found', { status: 404 });
  }

  private async registerResource(resource: ResourceMetadata): Promise<Response> {
    const id = this.getResourceId(resource.type, resource.namespace, resource.key);

    const existing = this.resources.get(id);
    if (existing) {
      // Update existing resource
      resource.created_at = existing.created_at;
      resource.updated_at = new Date().toISOString();
    } else {
      // New resource
      resource.created_at = new Date().toISOString();
      resource.updated_at = resource.created_at;
    }

    this.resources.set(id, resource);

    // Persist to storage
    await this.state.storage.put('resources', Object.fromEntries(this.resources));

    return new Response(JSON.stringify({
      success: true,
      resource_id: id,
      resource,
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  private async unregisterResource(type: string, namespace: string, key: string): Promise<Response> {
    const id = this.getResourceId(type, namespace, key);

    if (!this.resources.has(id)) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Resource not found',
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    this.resources.delete(id);
    await this.state.storage.put('resources', Object.fromEntries(this.resources));

    return new Response(JSON.stringify({
      success: true,
      resource_id: id,
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  private async listResources(query: ResourceQuery): Promise<Response> {
    let resources = Array.from(this.resources.values());

    // Apply filters
    if (query.type) {
      resources = resources.filter(r => r.type === query.type);
    }
    if (query.namespace) {
      resources = resources.filter(r => r.namespace === query.namespace);
    }
    if (query.key_prefix) {
      resources = resources.filter(r => r.key.startsWith(query.key_prefix));
    }

    // Sort by updated_at desc
    resources.sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());

    // Pagination
    const total = resources.length;
    const offset = query.offset || 0;
    const limit = query.limit || 100;
    resources = resources.slice(offset, offset + limit);

    return new Response(JSON.stringify({
      resources,
      total,
      offset,
      limit,
      has_more: offset + limit < total,
    }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  private async getStats(): Promise<Response> {
    const resources = Array.from(this.resources.values());

    const stats = {
      total: resources.length,
      by_type: {
        kv: resources.filter(r => r.type === 'kv').length,
        d1: resources.filter(r => r.type === 'd1').length,
        r2: resources.filter(r => r.type === 'r2').length,
        do: resources.filter(r => r.type === 'do').length,
      },
      by_namespace: {} as Record<string, number>,
      total_size: resources.reduce((sum, r) => sum + (r.size || 0), 0),
    };

    // Count by namespace
    for (const resource of resources) {
      stats.by_namespace[resource.namespace] = (stats.by_namespace[resource.namespace] || 0) + 1;
    }

    return new Response(JSON.stringify(stats), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  private getResourceId(type: string, namespace: string, key: string): string {
    return `${type}:${namespace}:${key}`;
  }
}
