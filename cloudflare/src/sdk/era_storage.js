/**
 * ERA Storage SDK for JavaScript/Node.js
 * Provides easy access to KV, D1, R2 storage from sandboxed code
 */

// Get storage URL from environment
const STORAGE_URL = process.env.ERA_STORAGE_URL || 'http://localhost';

/**
 * Key-Value storage interface
 */
class KVStorage {
  /**
   * Set a key-value pair
   * @param {string} namespace - The namespace
   * @param {string} key - The key
   * @param {string} value - The value
   * @param {Object} [metadata] - Optional metadata
   * @returns {Promise<boolean>}
   */
  static async set(namespace, key, value, metadata = null) {
    const url = `${STORAGE_URL}/api/storage/kv/${namespace}/${key}`;

    const response = await fetch(url, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ value, metadata })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`KV set failed: ${error.error}`);
    }

    const result = await response.json();
    return result.success || false;
  }

  /**
   * Get a value by key
   * @param {string} namespace - The namespace
   * @param {string} key - The key
   * @returns {Promise<string|null>}
   */
  static async get(namespace, key) {
    const url = `${STORAGE_URL}/api/storage/kv/${namespace}/${key}`;

    const response = await fetch(url);

    if (response.status === 404) {
      return null;
    }

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`KV get failed: ${error.error}`);
    }

    const result = await response.json();
    return result.value || null;
  }

  /**
   * Delete a key
   * @param {string} namespace - The namespace
   * @param {string} key - The key
   * @returns {Promise<boolean>}
   */
  static async delete(namespace, key) {
    const url = `${STORAGE_URL}/api/storage/kv/${namespace}/${key}`;

    const response = await fetch(url, { method: 'DELETE' });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`KV delete failed: ${error.error}`);
    }

    const result = await response.json();
    return result.success || false;
  }

  /**
   * List keys in a namespace
   * @param {string} namespace - The namespace
   * @param {string} [prefix=''] - Key prefix filter
   * @param {number} [limit=100] - Max results
   * @returns {Promise<Array>}
   */
  static async list(namespace, prefix = '', limit = 100) {
    const url = `${STORAGE_URL}/api/storage/kv/${namespace}?prefix=${encodeURIComponent(prefix)}&limit=${limit}`;

    const response = await fetch(url);

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`KV list failed: ${error.error}`);
    }

    const result = await response.json();
    return result.keys || [];
  }
}

/**
 * D1 SQL database interface
 */
class D1Storage {
  /**
   * Execute a SELECT query and return results
   * @param {string} namespace - The namespace
   * @param {string} sql - The SQL query
   * @param {Array} [params=[]] - Query parameters
   * @returns {Promise<Array>}
   */
  static async query(namespace, sql, params = []) {
    const url = `${STORAGE_URL}/api/storage/d1/${namespace}/query`;

    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sql, params })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`D1 query failed: ${error.error}`);
    }

    const result = await response.json();
    return result.results || [];
  }

  /**
   * Execute a statement (INSERT, UPDATE, DELETE, CREATE TABLE, etc.)
   * @param {string} namespace - The namespace
   * @param {string} sql - The SQL statement
   * @param {Array} [params=[]] - Statement parameters
   * @returns {Promise<Object>}
   */
  static async exec(namespace, sql, params = []) {
    const url = `${STORAGE_URL}/api/storage/d1/${namespace}/exec`;

    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sql, params })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`D1 exec failed: ${error.error}`);
    }

    return await response.json();
  }
}

/**
 * R2 Object storage interface
 */
class R2Storage {
  /**
   * Store an object
   * @param {string} namespace - The namespace
   * @param {string} key - The object key
   * @param {Buffer|Uint8Array|string} content - The content (will be converted to base64)
   * @param {Object} [metadata=null] - Optional metadata
   * @returns {Promise<boolean>}
   */
  static async put(namespace, key, content, metadata = null) {
    const url = `${STORAGE_URL}/api/storage/r2/${namespace}/${key}`;

    // Convert content to base64
    let contentB64;
    if (typeof content === 'string') {
      contentB64 = Buffer.from(content).toString('base64');
    } else if (content instanceof Buffer) {
      contentB64 = content.toString('base64');
    } else if (content instanceof Uint8Array) {
      contentB64 = Buffer.from(content).toString('base64');
    } else {
      throw new Error('Content must be string, Buffer, or Uint8Array');
    }

    const response = await fetch(url, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: contentB64, metadata })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`R2 put failed: ${error.error}`);
    }

    const result = await response.json();
    return result.success || false;
  }

  /**
   * Retrieve an object
   * @param {string} namespace - The namespace
   * @param {string} key - The object key
   * @returns {Promise<Buffer|null>}
   */
  static async get(namespace, key) {
    const url = `${STORAGE_URL}/api/storage/r2/${namespace}/${key}`;

    const response = await fetch(url);

    if (response.status === 404) {
      return null;
    }

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`R2 get failed: ${error.error}`);
    }

    const result = await response.json();
    if (result.content) {
      return Buffer.from(result.content, 'base64');
    }
    return null;
  }

  /**
   * Delete an object
   * @param {string} namespace - The namespace
   * @param {string} key - The object key
   * @returns {Promise<boolean>}
   */
  static async delete(namespace, key) {
    const url = `${STORAGE_URL}/api/storage/r2/${namespace}/${key}`;

    const response = await fetch(url, { method: 'DELETE' });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`R2 delete failed: ${error.error}`);
    }

    const result = await response.json();
    return result.success || false;
  }

  /**
   * List objects in a namespace
   * @param {string} namespace - The namespace
   * @param {string} [prefix=''] - Key prefix filter
   * @param {number} [limit=100] - Max results
   * @returns {Promise<Array>}
   */
  static async list(namespace, prefix = '', limit = 100) {
    const url = `${STORAGE_URL}/api/storage/r2/${namespace}?prefix=${encodeURIComponent(prefix)}&limit=${limit}`;

    const response = await fetch(url);

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`R2 list failed: ${error.error}`);
    }

    const result = await response.json();
    return result.objects || [];
  }
}

// Export for CommonJS
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { KVStorage, D1Storage, R2Storage };
}

// Example usage:
if (require.main === module) {
  (async () => {
    // KV example
    await KVStorage.set("app1", "user:123", JSON.stringify({ name: "Alice", age: 30 }));
    const userData = JSON.parse(await KVStorage.get("app1", "user:123"));
    console.log("User:", userData);

    // D1 example
    await D1Storage.exec("app1", "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)");
    await D1Storage.exec("app1", "INSERT INTO users (name) VALUES (?)", ["Bob"]);
    const users = await D1Storage.query("app1", "SELECT * FROM users");
    console.log("Users:", users);

    // R2 example
    await R2Storage.put("app1", "file.txt", "Hello World!");
    const content = await R2Storage.get("app1", "file.txt");
    console.log("File content:", content.toString());
  })();
}
