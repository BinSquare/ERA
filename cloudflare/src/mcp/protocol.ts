// MCP Protocol Implementation (JSON-RPC 2.0 over SSE)

import { JSONRPCRequest, JSONRPCResponse, JSONRPCError, JSONRPC_ERRORS } from './types';

/**
 * Create a JSON-RPC success response
 */
export function createSuccessResponse(id: string | number | undefined, result: any): JSONRPCResponse {
  return {
    jsonrpc: '2.0',
    id,
    result,
  };
}

/**
 * Create a JSON-RPC error response
 */
export function createErrorResponse(
  id: string | number | undefined,
  code: number,
  message: string,
  data?: any
): JSONRPCResponse {
  return {
    jsonrpc: '2.0',
    id,
    error: {
      code,
      message,
      data,
    },
  };
}

/**
 * Validate JSON-RPC request
 */
export function validateJSONRPCRequest(req: any): req is JSONRPCRequest {
  return (
    req &&
    typeof req === 'object' &&
    req.jsonrpc === '2.0' &&
    typeof req.method === 'string'
  );
}

/**
 * Parse JSON-RPC request from request body
 */
export async function parseJSONRPCRequest(request: Request): Promise<JSONRPCRequest> {
  try {
    const body = await request.json();

    if (!validateJSONRPCRequest(body)) {
      throw new Error('Invalid JSON-RPC request');
    }

    return body;
  } catch (error) {
    throw new Error(`Failed to parse JSON-RPC request: ${error}`);
  }
}

/**
 * Create a JSON response
 */
export function jsonResponse(data: any, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
}

/**
 * Create an SSE (Server-Sent Events) response
 * For streaming MCP responses
 */
export function createSSEResponse(stream: ReadableStream): Response {
  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

/**
 * Format data as SSE message
 */
export function formatSSEMessage(data: any): string {
  return `data: ${JSON.stringify(data)}\n\n`;
}

/**
 * Create an SSE stream from messages
 */
export function createSSEStream(messages: any[]): ReadableStream {
  const encoder = new TextEncoder();

  return new ReadableStream({
    start(controller) {
      for (const message of messages) {
        controller.enqueue(encoder.encode(formatSSEMessage(message)));
      }
      controller.close();
    },
  });
}

/**
 * Handle CORS preflight
 */
export function handleCORS(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '86400',
    },
  });
}

/**
 * Wrap handler with error handling
 */
export function withErrorHandling(
  handler: (req: JSONRPCRequest) => Promise<any>
): (req: JSONRPCRequest) => Promise<JSONRPCResponse> {
  return async (req: JSONRPCRequest): Promise<JSONRPCResponse> => {
    try {
      const result = await handler(req);
      return createSuccessResponse(req.id, result);
    } catch (error: any) {
      console.error('MCP Handler Error:', error);
      return createErrorResponse(
        req.id,
        JSONRPC_ERRORS.INTERNAL_ERROR,
        error.message || 'Internal error',
        error.stack
      );
    }
  };
}
