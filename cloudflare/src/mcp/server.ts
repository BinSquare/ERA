// MCP Server
// Main request handler for MCP protocol endpoints

import { JSONRPCRequest, JSONRPC_ERRORS } from './types';
import {
  parseJSONRPCRequest,
  createSuccessResponse,
  createErrorResponse,
  jsonResponse,
  handleCORS,
} from './protocol';
import {
  getTools,
  handleExecuteCode,
  handleCreateSession,
  handleRunInSession,
  handleListSessions,
  handleGetSession,
  handleDeleteSession,
  handleUploadFile,
  handleReadFile,
  handleListFiles,
} from './tools';
import { listResources, readResource } from './resources';

/**
 * Main MCP server handler
 */
export async function handleMCPRequest(
  request: Request,
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  // Handle CORS preflight
  if (request.method === 'OPTIONS') {
    return handleCORS();
  }

  // Parse JSON-RPC request
  let rpcRequest: JSONRPCRequest;
  try {
    rpcRequest = await parseJSONRPCRequest(request);
  } catch (error: any) {
    return jsonResponse(
      createErrorResponse(
        undefined,
        JSONRPC_ERRORS.PARSE_ERROR,
        'Parse error',
        error.message
      )
    );
  }

  // Route to appropriate handler
  try {
    const result = await routeRequest(rpcRequest, env, ctx);
    return jsonResponse(createSuccessResponse(rpcRequest.id, result));
  } catch (error: any) {
    console.error('MCP Error:', error);
    return jsonResponse(
      createErrorResponse(
        rpcRequest.id,
        JSONRPC_ERRORS.INTERNAL_ERROR,
        error.message || 'Internal error',
        error.stack
      )
    );
  }
}

/**
 * Route JSON-RPC request to the appropriate handler
 */
async function routeRequest(
  request: JSONRPCRequest,
  env: Env,
  ctx: ExecutionContext
): Promise<any> {
  const { method, params } = request;

  // Get Durable Object stub for API calls
  const stub = env.ERA_AGENT.get(env.ERA_AGENT.idFromName('primary'));

  switch (method) {
    // Protocol methods
    case 'initialize':
      return handleInitialize(params);

    // Tools methods
    case 'tools/list':
      return handleToolsList();

    case 'tools/call':
      return handleToolsCall(params, env, ctx, stub);

    // Resources methods
    case 'resources/list':
      return handleResourcesList(env);

    case 'resources/read':
      return handleResourcesRead(params, env);

    default:
      throw new Error(`Method not found: ${method}`);
  }
}

/**
 * Handle initialize request
 */
function handleInitialize(params: any): any {
  return {
    protocolVersion: '0.1.0',
    capabilities: {
      tools: {},
      resources: {
        subscribe: false,
        listChanged: false,
      },
    },
    serverInfo: {
      name: 'era-agent-mcp',
      version: '1.0.0',
    },
  };
}

/**
 * Handle tools/list request
 */
function handleToolsList(): any {
  return {
    tools: getTools(),
  };
}

/**
 * Handle tools/call request
 */
async function handleToolsCall(
  params: any,
  env: Env,
  ctx: ExecutionContext,
  stub: DurableObjectStub
): Promise<any> {
  const { name, arguments: args } = params;

  if (!name) {
    throw new Error('Missing tool name');
  }

  // Route to appropriate tool handler
  switch (name) {
    case 'era_execute_code':
      return await handleExecuteCode(args, env, stub);

    case 'era_create_session':
      return await handleCreateSession(args, env, ctx);

    case 'era_run_in_session':
      return await handleRunInSession(args, env);

    case 'era_list_sessions':
      return await handleListSessions(env);

    case 'era_get_session':
      return await handleGetSession(args, env);

    case 'era_delete_session':
      return await handleDeleteSession(args, env);

    case 'era_upload_file':
      return await handleUploadFile(args, env);

    case 'era_read_file':
      return await handleReadFile(args, env);

    case 'era_list_files':
      return await handleListFiles(args, env);

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

/**
 * Handle resources/list request
 */
async function handleResourcesList(env: Env): Promise<any> {
  const resources = await listResources(env);
  return {
    resources,
  };
}

/**
 * Handle resources/read request
 */
async function handleResourcesRead(params: any, env: Env): Promise<any> {
  const { uri } = params;

  if (!uri) {
    throw new Error('Missing resource URI');
  }

  const contents = await readResource(uri, env);
  return {
    contents,
  };
}
