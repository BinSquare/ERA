// Type definitions for ERA Agent

import { EraAgent } from './index';
import { SessionDO } from './session';
import { StorageRegistry } from './storage-registry';

export interface Env {
  // Container binding
  ERA_AGENT: DurableObjectNamespace<EraAgent>;

  // Durable Object bindings
  SESSIONS: DurableObjectNamespace<SessionDO>;
  STORAGE_REGISTRY: DurableObjectNamespace<StorageRegistry>;

  // Storage bindings
  SESSIONS_BUCKET: R2Bucket;        // R2 bucket for session files
  ERA_R2: R2Bucket;                 // R2 bucket for storage proxy
  ERA_KV: KVNamespace;              // KV namespace for storage proxy
  ERA_D1: D1Database;               // D1 database for storage proxy

  // Static assets binding (Astro site)
  ASSETS: Fetcher;                  // Static assets served from ./site/dist

  // Environment variables
  ERA_AGENT_IMAGE?: string;         // Optional: custom Docker image
  ERA_STORAGE_URL?: string;         // Optional: URL for storage proxy (for VMs to access storage)
}
