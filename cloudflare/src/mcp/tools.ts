// MCP Tool Handlers
// Wraps existing ERA Agent API functions with MCP protocol formatting

import { MCPTool, MCPToolResponse } from './types';
import {
  handleExecute,
  handleCreateSession as apiCreateSession,
  handleSessionRun,
  handleGetSession as apiGetSession,
  handleListSessions as apiListSessions,
  handleDeleteSession as apiDeleteSession,
  handleListSessionFiles as apiListSessionFiles,
  handleUploadSessionFile,
  handleDownloadSessionFile,
} from '../index';

/**
 * Get list of all available MCP tools
 */
export function getTools(): MCPTool[] {
  return [
    {
      name: 'era_execute_code',
      description: 'Execute code in an ephemeral environment. Supports Python, Node.js, TypeScript, Go, and Deno. The environment is automatically cleaned up after execution.',
      inputSchema: {
        type: 'object',
        properties: {
          code: {
            type: 'string',
            description: 'The code to execute',
          },
          language: {
            type: 'string',
            description: 'Programming language',
            enum: ['python', 'node', 'typescript', 'go', 'deno'],
          },
          files: {
            type: 'object',
            description: 'Optional files to create before execution (filename -> content)',
          },
          envs: {
            type: 'object',
            description: 'Optional environment variables',
          },
          timeout: {
            type: 'number',
            description: 'Execution timeout in seconds (default: 30)',
          },
          allowInternetAccess: {
            type: 'boolean',
            description: 'Allow internet access (default: true)',
          },
        },
        required: ['code', 'language'],
      },
    },
    {
      name: 'era_create_session',
      description: 'Create a persistent execution session. Sessions maintain state across multiple code executions.',
      inputSchema: {
        type: 'object',
        properties: {
          language: {
            type: 'string',
            description: 'Programming language for the session',
            enum: ['python', 'node', 'typescript', 'go', 'deno'],
          },
          persistent: {
            type: 'boolean',
            description: 'Enable file persistence (default: false)',
          },
          allowInternetAccess: {
            type: 'boolean',
            description: 'Allow internet access (default: true)',
          },
          default_timeout: {
            type: 'number',
            description: 'Default timeout for executions in this session (seconds)',
          },
        },
        required: ['language'],
      },
    },
    {
      name: 'era_run_in_session',
      description: 'Execute code in an existing session. State is maintained between executions.',
      inputSchema: {
        type: 'object',
        properties: {
          session_id: {
            type: 'string',
            description: 'Session ID from era_create_session',
          },
          code: {
            type: 'string',
            description: 'Code to execute',
          },
          timeout: {
            type: 'number',
            description: 'Execution timeout in seconds',
          },
          env: {
            type: 'object',
            description: 'Environment variables for this execution',
          },
        },
        required: ['session_id', 'code'],
      },
    },
    {
      name: 'era_list_sessions',
      description: 'List all active sessions',
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'era_get_session',
      description: 'Get details about a specific session',
      inputSchema: {
        type: 'object',
        properties: {
          session_id: {
            type: 'string',
            description: 'Session ID to query',
          },
        },
        required: ['session_id'],
      },
    },
    {
      name: 'era_delete_session',
      description: 'Delete a session and clean up its resources',
      inputSchema: {
        type: 'object',
        properties: {
          session_id: {
            type: 'string',
            description: 'Session ID to delete',
          },
        },
        required: ['session_id'],
      },
    },
    {
      name: 'era_upload_file',
      description: 'Upload a file to a session workspace',
      inputSchema: {
        type: 'object',
        properties: {
          session_id: {
            type: 'string',
            description: 'Target session ID',
          },
          path: {
            type: 'string',
            description: 'File path in the session workspace',
          },
          content: {
            type: 'string',
            description: 'File content',
          },
        },
        required: ['session_id', 'path', 'content'],
      },
    },
    {
      name: 'era_read_file',
      description: 'Read a file from a session workspace',
      inputSchema: {
        type: 'object',
        properties: {
          session_id: {
            type: 'string',
            description: 'Source session ID',
          },
          path: {
            type: 'string',
            description: 'File path to read',
          },
        },
        required: ['session_id', 'path'],
      },
    },
    {
      name: 'era_list_files',
      description: 'List all files in a session workspace',
      inputSchema: {
        type: 'object',
        properties: {
          session_id: {
            type: 'string',
            description: 'Session ID to query',
          },
        },
        required: ['session_id'],
      },
    },
  ];
}

/**
 * Handle era_execute_code tool call
 */
export async function handleExecuteCode(
  args: any,
  env: Env,
  stub: DurableObjectStub
): Promise<MCPToolResponse> {
  const { code, language, files, envs, timeout, allowInternetAccess } = args;

  // Validate required arguments
  if (!code || !language) {
    throw new Error('Missing required arguments: code and language');
  }

  // Create Request for handleExecute
  const apiRequest = new Request('http://internal/api/execute', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code,
      language,
      files,
      envs,
      timeout,
      allowInternetAccess,
    }),
  });

  // Call the exported handleExecute function directly
  const response = await handleExecute(apiRequest, stub);
  const result = await response.json();

  if (!response.ok) {
    throw new Error(result.error || 'Execution failed');
  }

  // Format as MCP response
  return {
    content: [
      {
        type: 'text',
        text: formatExecutionResult(result),
      },
    ],
  };
}

/**
 * Handle era_create_session tool call
 */
export async function handleCreateSession(
  args: any,
  env: Env,
  ctx: ExecutionContext
): Promise<MCPToolResponse> {
  const { language, persistent, allowInternetAccess, default_timeout } = args;

  if (!language) {
    throw new Error('Missing required argument: language');
  }

  // Create Request for handleCreateSession
  const apiRequest = new Request('http://internal/api/sessions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      language,
      persistent,
      allowInternetAccess,
      default_timeout,
    }),
  });

  // Call the exported handleCreateSession function directly
  const response = await apiCreateSession(apiRequest, env, ctx);
  const result = await response.json();

  if (!response.ok) {
    throw new Error(result.error || 'Session creation failed');
  }

  return {
    content: [
      {
        type: 'text',
        text: `Session created successfully!\n\nSession ID: ${result.id}\nLanguage: ${result.language}\nPersistent: ${result.persistent}\n\nYou can now use era_run_in_session to execute code in this session.`,
      },
    ],
  };
}

/**
 * Handle era_run_in_session tool call
 */
export async function handleRunInSession(
  args: any,
  env: Env
): Promise<MCPToolResponse> {
  const { session_id, code, timeout, env: envVars } = args;

  if (!session_id || !code) {
    throw new Error('Missing required arguments: session_id and code');
  }

  // Create Request for handleSessionRun
  const apiRequest = new Request(`http://internal/api/sessions/${session_id}/run`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code,
      timeout,
      env: envVars,
    }),
  });

  const response = await handleSessionRun(session_id, apiRequest, env);
  const result = await response.json();

  if (!response.ok) {
    throw new Error(result.error || 'Execution failed');
  }

  return {
    content: [
      {
        type: 'text',
        text: formatExecutionResult(result),
      },
    ],
  };
}

/**
 * Handle era_list_sessions tool call
 */
export async function handleListSessions(env: Env): Promise<MCPToolResponse> {
  const response = await apiListSessions(env);
  const sessions = await response.json();

  if (!response.ok) {
    throw new Error('Failed to list sessions');
  }

  if (!Array.isArray(sessions) || sessions.length === 0) {
    return {
      content: [
        {
          type: 'text',
          text: 'No active sessions.',
        },
      ],
    };
  }

  const sessionList = sessions.map((s: any) =>
    `- ${s.id}\n  Language: ${s.language}\n  Persistent: ${s.persistent}\n  Created: ${s.created_at}`
  ).join('\n\n');

  return {
    content: [
      {
        type: 'text',
        text: `Active Sessions (${sessions.length}):\n\n${sessionList}`,
      },
    ],
  };
}

/**
 * Handle era_get_session tool call
 */
export async function handleGetSession(
  args: any,
  env: Env
): Promise<MCPToolResponse> {
  const { session_id } = args;

  if (!session_id) {
    throw new Error('Missing required argument: session_id');
  }

  const response = await apiGetSession(session_id, env);
  const session = await response.json();

  if (!response.ok) {
    throw new Error(session.error || 'Session not found');
  }

  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(session, null, 2),
      },
    ],
  };
}

/**
 * Handle era_delete_session tool call
 */
export async function handleDeleteSession(
  args: any,
  env: Env
): Promise<MCPToolResponse> {
  const { session_id } = args;

  if (!session_id) {
    throw new Error('Missing required argument: session_id');
  }

  const response = await apiDeleteSession(session_id, env);

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to delete session');
  }

  return {
    content: [
      {
        type: 'text',
        text: `Session ${session_id} deleted successfully.`,
      },
    ],
  };
}

/**
 * Handle era_upload_file tool call
 */
export async function handleUploadFile(
  args: any,
  env: Env
): Promise<MCPToolResponse> {
  const { session_id, path, content } = args;

  if (!session_id || !path || content === undefined) {
    throw new Error('Missing required arguments: session_id, path, and content');
  }

  const apiRequest = new Request(`http://internal/api/sessions/${session_id}/files/${path}`, {
    method: 'PUT',
    body: content,
  });

  const response = await handleUploadSessionFile(session_id, path, apiRequest, env);

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to upload file');
  }

  return {
    content: [
      {
        type: 'text',
        text: `File uploaded successfully: ${path}\nSession: ${session_id}`,
      },
    ],
  };
}

/**
 * Handle era_read_file tool call
 */
export async function handleReadFile(
  args: any,
  env: Env
): Promise<MCPToolResponse> {
  const { session_id, path } = args;

  if (!session_id || !path) {
    throw new Error('Missing required arguments: session_id and path');
  }

  const response = await handleDownloadSessionFile(session_id, path, env);

  if (!response.ok) {
    throw new Error('File not found or could not be read');
  }

  const content = await response.text();

  return {
    content: [
      {
        type: 'text',
        text: `File: ${path}\n\nContent:\n${content}`,
      },
    ],
  };
}

/**
 * Handle era_list_files tool call
 */
export async function handleListFiles(
  args: any,
  env: Env
): Promise<MCPToolResponse> {
  const { session_id } = args;

  if (!session_id) {
    throw new Error('Missing required argument: session_id');
  }

  const response = await apiListSessionFiles(session_id, env);
  const files = await response.json();

  if (!response.ok) {
    throw new Error(files.error || 'Failed to list files');
  }

  if (!Array.isArray(files) || files.length === 0) {
    return {
      content: [
        {
          type: 'text',
          text: `No files in session ${session_id}`,
        },
      ],
    };
  }

  const fileList = files.map((f: any) =>
    `- ${f.path} (${formatBytes(f.size)})`
  ).join('\n');

  return {
    content: [
      {
        type: 'text',
        text: `Files in session ${session_id}:\n\n${fileList}`,
      },
    ],
  };
}

/**
 * Format execution result for display
 */
function formatExecutionResult(result: any): string {
  let output = '';

  if (result.exit_code !== undefined) {
    output += `Exit Code: ${result.exit_code}\n\n`;
  }

  if (result.stdout) {
    output += `Stdout:\n${result.stdout}\n\n`;
  }

  if (result.stderr) {
    output += `Stderr:\n${result.stderr}\n\n`;
  }

  if (result.duration) {
    output += `Duration: ${result.duration}`;
  }

  return output.trim();
}

/**
 * Format bytes for display
 */
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${Math.round(bytes / Math.pow(k, i) * 100) / 100} ${sizes[i]}`;
}
