// MCP Resource Handlers
// Provides access to session metadata and files as resources

import { MCPResource, MCPResourceContent } from './types';

/**
 * List all available resources
 */
export async function listResources(env: Env): Promise<MCPResource[]> {
  // Get all sessions
  const apiRequest = new Request('http://internal/api/sessions', {
    method: 'GET',
  });

  const response = await env.ERA_AGENT.get(env.ERA_AGENT.idFromName('primary')).fetch(apiRequest);

  if (!response.ok) {
    return [];
  }

  const sessions = await response.json();

  if (!Array.isArray(sessions)) {
    return [];
  }

  const resources: MCPResource[] = [];

  for (const session of sessions) {
    const sessionId = session.id;

    // Add session metadata resource
    resources.push({
      uri: `session://${sessionId}`,
      name: `Session: ${sessionId}`,
      description: `Metadata for ${session.language} session`,
      mimeType: 'application/json',
    });

    // Add files resource
    resources.push({
      uri: `session://${sessionId}/files`,
      name: `Files in ${sessionId}`,
      description: `List of files in session ${sessionId}`,
      mimeType: 'application/json',
    });
  }

  return resources;
}

/**
 * Read a specific resource
 */
export async function readResource(
  uri: string,
  env: Env
): Promise<MCPResourceContent[]> {
  // Parse URI format: session://{id} or session://{id}/files
  if (!uri.startsWith('session://')) {
    throw new Error(`Invalid resource URI: ${uri}`);
  }

  const path = uri.replace('session://', '');
  const parts = path.split('/');
  const sessionId = parts[0];
  const resourceType = parts[1]; // undefined for session metadata, 'files' for files list

  if (!sessionId) {
    throw new Error('Invalid resource URI: missing session ID');
  }

  if (!resourceType) {
    // Read session metadata
    return await readSessionMetadata(sessionId, env);
  } else if (resourceType === 'files') {
    // Read files list
    return await readSessionFiles(sessionId, env);
  } else {
    throw new Error(`Unknown resource type: ${resourceType}`);
  }
}

/**
 * Read session metadata resource
 */
async function readSessionMetadata(
  sessionId: string,
  env: Env
): Promise<MCPResourceContent[]> {
  const apiRequest = new Request(`http://internal/api/sessions/${sessionId}`, {
    method: 'GET',
  });

  const response = await env.ERA_AGENT.get(env.ERA_AGENT.idFromName('primary')).fetch(apiRequest);

  if (!response.ok) {
    throw new Error(`Session ${sessionId} not found`);
  }

  const session = await response.json();

  return [
    {
      uri: `session://${sessionId}`,
      mimeType: 'application/json',
      text: JSON.stringify(session, null, 2),
    },
  ];
}

/**
 * Read session files list resource
 */
async function readSessionFiles(
  sessionId: string,
  env: Env
): Promise<MCPResourceContent[]> {
  const apiRequest = new Request(`http://internal/api/sessions/${sessionId}/files`, {
    method: 'GET',
  });

  const response = await env.ERA_AGENT.get(env.ERA_AGENT.idFromName('primary')).fetch(apiRequest);

  if (!response.ok) {
    throw new Error(`Failed to list files for session ${sessionId}`);
  }

  const files = await response.json();

  return [
    {
      uri: `session://${sessionId}/files`,
      mimeType: 'application/json',
      text: JSON.stringify(files, null, 2),
    },
  ];
}
